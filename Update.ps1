# Update.ps1
# 为 Aria2 超·懒人包更新 aria2-next（aria2c.exe）与 AriaNg（AllInOne）
# 逻辑对齐 .github/workflows/release.yml：
#   - 读取 AnInsomniacy/aria2-next、mayswind/AriaNg 的 latest release
#   - 下载 Windows 可执行文件，并用上游 checksums.sha256 校验 SHA-256
#   - 下载 AriaNg AllInOne.zip，解压到 AriaNg 目录
# 用法：
#   右键以管理员运行 Update.bat
#   或：powershell -ExecutionPolicy Bypass -File .\Update.ps1
# 可选参数：
#   -Force     即使本地已是最新也重新下载替换
#   -NoPause   结束后不暂停（给 Update.bat 用）

param(
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$UpdaterUserAgent = "Aria2-SuperLazyPackage-Updater"
$Aria2Repo = "AnInsomniacy/aria2-next"
$AriaNgRepo = "mayswind/AriaNg"
$ServiceName = "Aria2Service"
$VersionFileName = "upstream.versions"

# GitHub 直连失败时依次尝试的前缀（国内网络常用）
$DownloadMirrors = @(
    "",
    "https://ghproxy.com/",
    "https://ghfast.top/",
    "https://gh-proxy.com/"
)

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Get-WindowsAssetArch {
    $pa = [string]$env:PROCESSOR_ARCHITECTURE
    $paWow = [string]$env:PROCESSOR_ARCHITEW6432
    if ($pa -eq "ARM64" -or $paWow -eq "ARM64") {
        return "windows-arm64"
    }
    return "windows-x86_64"
}

function ConvertTo-MirrorUrl {
    param(
        [string]$Url,
        [string]$Prefix
    )
    if ([string]::IsNullOrEmpty($Prefix)) {
        return $Url
    }
    return ($Prefix.TrimEnd("/") + "/" + $Url)
}

function Save-Url {
    param(
        [string]$Url,
        [string]$OutFile
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add($Url)
    foreach ($prefix in $DownloadMirrors) {
        if (-not [string]::IsNullOrEmpty($prefix)) {
            [void]$candidates.Add((ConvertTo-MirrorUrl -Url $Url -Prefix $prefix))
        }
    }

    $lastError = $null
    foreach ($candidate in $candidates) {
        try {
            Write-Host "  -> $candidate"
            $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
            if ($curl) {
                & curl.exe -L --fail --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 -A $UpdaterUserAgent -o $OutFile $candidate
                if ($LASTEXITCODE -ne 0) {
                    throw "curl 退出码 $LASTEXITCODE"
                }
            } else {
                Invoke-WebRequest -Uri $candidate -OutFile $OutFile -UseBasicParsing -UserAgent $UpdaterUserAgent -TimeoutSec 180
            }
            if (-not (Test-Path -LiteralPath $OutFile)) {
                throw "文件未写入"
            }
            if ((Get-Item -LiteralPath $OutFile).Length -le 0) {
                throw "下载文件为空"
            }
            return
        } catch {
            $lastError = $_
            Write-Warn "     失败：$($_.Exception.Message)"
            if (Test-Path -LiteralPath $OutFile) {
                Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    throw "无法下载 $Url ；最后错误：$lastError"
}

function Get-GitHubLatestRelease {
    param([string]$Repo)

    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{
        "User-Agent" = $UpdaterUserAgent
        "Accept"     = "application/vnd.github+json"
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add($apiUrl)
    foreach ($prefix in $DownloadMirrors) {
        if (-not [string]::IsNullOrEmpty($prefix)) {
            [void]$candidates.Add((ConvertTo-MirrorUrl -Url $apiUrl -Prefix $prefix))
        }
    }

    $lastError = $null
    foreach ($candidate in $candidates) {
        try {
            Write-Host "  -> $candidate"
            return Invoke-RestMethod -Uri $candidate -Headers $headers -TimeoutSec 30
        } catch {
            $lastError = $_
            Write-Warn "     失败：$($_.Exception.Message)"
        }
    }
    throw "无法读取 $Repo 的 latest release。最后错误：$lastError"
}

function Find-ReleaseAsset {
    param(
        $Release,
        [string]$Pattern,
        [string]$What
    )

    $assets = @($Release.assets)
    $found = @($assets | Where-Object { $_.name -match $Pattern })
    if ($found.Count -ne 1) {
        $names = ($assets | ForEach-Object { $_.name }) -join ", "
        throw "在 $($Release.tag_name) 中期望恰好 1 个${What}资源（/$Pattern/），实际 $($found.Count) 个。资源列表：$names"
    }
    return $found[0]
}

function Get-ExpectedSha256 {
    param(
        [string]$ChecksumPath,
        [string]$AssetName
    )

    $lines = Get-Content -LiteralPath $ChecksumPath -ErrorAction Stop
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ([string]::IsNullOrEmpty($trim) -or $trim.StartsWith("#")) {
            continue
        }
        if ($trim -match "^([A-Fa-f0-9]{64})\s+\*?(\S+)\s*$") {
            if ($Matches[2] -eq $AssetName) {
                return $Matches[1].ToLowerInvariant()
            }
        }
    }
    throw "checksums.sha256 中找不到 $AssetName 的哈希"
}

function Read-VersionMap {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -match "^([^=]+)=(.*)$") {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

function Write-VersionMap {
    param(
        [string]$Path,
        [hashtable]$Map
    )

    $lines = @(
        "aria2-next=$($Map['aria2-next'])",
        "AriaNg=$($Map['AriaNg'])",
        "arch=$($Map['arch'])",
        "updated=$($Map['updated'])"
    )
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-ServiceObject {
    return Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

function Stop-Aria2ServiceIfNeeded {
    $svc = Get-ServiceObject
    if (-not $svc) {
        Write-Host "未找到 $ServiceName 服务，跳过停止。"
        return $false
    }
    if ($svc.Status -ne "Running") {
        Write-Host "$ServiceName 当前状态：$($svc.Status)"
        return $false
    }
    Write-Host "正在停止 $ServiceName ..."
    Stop-Service -Name $ServiceName -Force -ErrorAction Stop
    try {
        $svc.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
    } catch {
        Write-Warn "等待服务停止超时，继续尝试替换文件。"
    }
    return $true
}

function Start-Aria2ServiceIfNeeded {
    param([bool]$WasRunning)

    if (-not $WasRunning) {
        return
    }
    Write-Host "正在启动 $ServiceName ..."
    Start-Service -Name $ServiceName -ErrorAction Stop
    $svc = Get-ServiceObject
    if ($svc) {
        try {
            $svc.WaitForStatus("Running", [TimeSpan]::FromSeconds(20))
        } catch {
            Write-Warn "服务已发出启动命令，但尚未进入 Running 状态。"
        }
    }
    Write-Ok "$ServiceName 已启动。"
}

function Wait-FileUnlocked {
    param(
        [string]$Path,
        [int]$Tries = 12
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    for ($i = 0; $i -lt $Tries; $i++) {
        try {
            $stream = [System.IO.File]::Open($Path, "Open", "ReadWrite", "None")
            $stream.Close()
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "文件仍被占用，无法替换：$Path"
}

function Install-Aria2Exe {
    param(
        [string]$SourceExe,
        [string]$TargetExe
    )

    $targetDir = Split-Path -Parent $TargetExe
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
    }

    if (Test-Path -LiteralPath $TargetExe) {
        $backup = "$TargetExe.bak"
        Copy-Item -LiteralPath $TargetExe -Destination $backup -Force
        Wait-FileUnlocked -Path $TargetExe
    }
    Copy-Item -LiteralPath $SourceExe -Destination $TargetExe -Force
}

function Install-AriaNgZip {
    param(
        [string]$ZipPath,
        [string]$TargetDir,
        [string]$WorkDir
    )

    $extractDir = Join-Path $WorkDir "ariang-extract"
    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractDir | Out-Null

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractDir -Force

    $entries = @(Get-ChildItem -LiteralPath $extractDir -Force)
    $sourceDir = $extractDir
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
        $sourceDir = $entries[0].FullName
    }

    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
    } else {
        Get-ChildItem -LiteralPath $TargetDir -Force | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }

    Get-ChildItem -LiteralPath $sourceDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TargetDir $_.Name) -Recurse -Force
    }
}

# --- 入口 ---

$elevating = $false
$workDir = $null

try {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "需要 PowerShell 5.1 或更高版本。"
    }

    if (-not (Test-IsAdmin)) {
        $elevating = $true
        Write-Host "正在请求管理员权限（替换 aria2c.exe / 重启服务需要）..."
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($Force) { $argList += " -Force" }
        if ($NoPause) { $argList += " -NoPause" }
        $proc = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait -PassThru
        if ($null -eq $proc) {
            throw "未能提升权限。"
        }
        exit $proc.ExitCode
    }

    $RootDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($RootDir)) {
        $RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    Set-Location -LiteralPath $RootDir

    $Host.UI.RawUI.WindowTitle = "Aria2 超·懒人包 - 更新 aria2-next / AriaNg"
    try { chcp 65001 | Out-Null } catch { }

    Write-Host "=============================================="
    Write-Host " Aria2 超·懒人包  上游更新"
    Write-Host " 目录: $RootDir"
    Write-Host "=============================================="

    $arch = Get-WindowsAssetArch
    $exePattern = [regex]::Escape($arch) + "\.exe$"
    Write-Host "检测到架构：$arch"

    $versionPath = Join-Path $RootDir $VersionFileName
    $localVersions = Read-VersionMap -Path $versionPath

    Write-Step "[1/5] 查询上游 latest release"
    $aria2Release = Get-GitHubLatestRelease -Repo $Aria2Repo
    $ariangRelease = Get-GitHubLatestRelease -Repo $AriaNgRepo

    $aria2Tag = [string]$aria2Release.tag_name
    $ariangTag = [string]$ariangRelease.tag_name
    Write-Host "  aria2-next : $aria2Tag"
    Write-Host "  AriaNg     : $ariangTag"
    if ($localVersions["aria2-next"]) {
        Write-Host "  本地记录   : aria2-next=$($localVersions['aria2-next'])  AriaNg=$($localVersions['AriaNg'])"
    }

    $exeAsset = Find-ReleaseAsset -Release $aria2Release -Pattern $exePattern -What "Windows $arch exe"
    $sumAsset = Find-ReleaseAsset -Release $aria2Release -Pattern "checksums\.sha256$" -What "checksums.sha256"
    $zipAsset = Find-ReleaseAsset -Release $ariangRelease -Pattern "AllInOne\.zip$" -What "AllInOne.zip"

    $needAria2 = $Force -or ($localVersions["aria2-next"] -ne $aria2Tag) -or ($localVersions["arch"] -ne $arch) -or (-not (Test-Path -LiteralPath (Join-Path $RootDir "aria2c.exe")))
    $needAriaNg = $Force -or ($localVersions["AriaNg"] -ne $ariangTag) -or (-not (Test-Path -LiteralPath (Join-Path $RootDir "AriaNg\index.html")))

    if (-not $needAria2 -and -not $needAriaNg) {
        Write-Ok "已是最新，无需下载。若要强制重装，请加 -Force。"
        exit 0
    }

    $workDir = Join-Path $env:TEMP "Aria2-SuperLazyPackage-update"
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workDir | Out-Null

    $downloadedExe = $null
    $downloadedZip = $null

    if ($needAria2) {
        Write-Step "[2/5] 下载 aria2-next 并校验 SHA-256"
        Write-Host "  资源：$($exeAsset.name)"
        $downloadedExe = Join-Path $workDir "aria2c.exe"
        $checksumPath = Join-Path $workDir "checksums.sha256"
        Save-Url -Url $exeAsset.browser_download_url -OutFile $downloadedExe
        Save-Url -Url $sumAsset.browser_download_url -OutFile $checksumPath

        $expected = Get-ExpectedSha256 -ChecksumPath $checksumPath -AssetName $exeAsset.name
        $actual = (Get-FileHash -LiteralPath $downloadedExe -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host "  期望 SHA-256 : $expected"
        Write-Host "  实际 SHA-256 : $actual"
        if ($actual -ne $expected) {
            throw "SHA-256 校验失败，已中止（未改动现有 aria2c.exe）。"
        }
        Write-Ok "  校验通过。"
    } else {
        Write-Step "[2/5] aria2-next $aria2Tag 已是最新，跳过下载"
    }

    if ($needAriaNg) {
        Write-Step "[3/5] 下载 AriaNg AllInOne"
        Write-Host "  资源：$($zipAsset.name)"
        $downloadedZip = Join-Path $workDir "AriaNg-AllInOne.zip"
        Save-Url -Url $zipAsset.browser_download_url -OutFile $downloadedZip
        Write-Ok "  下载完成。"
    } else {
        Write-Step "[3/5] AriaNg $ariangTag 已是最新，跳过下载"
    }

    $wasRunning = $false
    Write-Step "[4/5] 替换本地文件"
    try {
        if ($needAria2) {
            $wasRunning = Stop-Aria2ServiceIfNeeded
            $targetExe = Join-Path $RootDir "aria2c.exe"
            Install-Aria2Exe -SourceExe $downloadedExe -TargetExe $targetExe
            Write-Ok "  已更新 aria2c.exe  （备份：aria2c.exe.bak）"
        }
        if ($needAriaNg) {
            $ariaNgDir = Join-Path $RootDir "AriaNg"
            Install-AriaNgZip -ZipPath $downloadedZip -TargetDir $ariaNgDir -WorkDir $workDir
            Write-Ok "  已更新 AriaNg\  （AllInOne）"
        }
    } finally {
        if ($wasRunning) {
            Start-Aria2ServiceIfNeeded -WasRunning $true
        }
    }

    Write-Step "[5/5] 写入版本记录"
    Write-VersionMap -Path $versionPath -Map @{
        "aria2-next" = $aria2Tag
        "AriaNg"     = $ariangTag
        "arch"       = $arch
        "updated"    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    Write-Ok "  $VersionFileName"

    Write-Host ""
    Write-Ok "更新完成。"
    Write-Host "  aria2-next $aria2Tag  ($arch)"
    Write-Host "  AriaNg     $ariangTag  (AllInOne)"
    Write-Host "  配置文件 aria2.conf / 会话 / DHT 均未改动。"
    exit 0
} catch {
    Write-Host ""
    Write-Host "更新失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($workDir -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $NoPause -and -not $elevating) {
        Write-Host ""
        Write-Host "按 Enter 退出..."
        try { [void](Read-Host) } catch { }
    }
}
