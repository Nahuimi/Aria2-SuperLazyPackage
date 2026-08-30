@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS1=%~dp0Update.ps1"
set "LOG=%~dp0Update.log"

echo ==============================================
echo  Aria2 SuperLazyPackage  Update
echo ==============================================
echo.

echo [%date% %time%] Update.bat start>>"%LOG%"

if not exist "%PS%" (
    echo [ERROR] powershell.exe not found.
    echo 找不到 PowerShell。
    echo.
    pause
    exit /b 1
)

if not exist "%PS1%" (
    echo [ERROR] Update.ps1 not found.
    echo 找不到 Update.ps1，必须和 Update.bat 放在同一个 Aria2 目录。
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if not %errorlevel%==0 (
    echo [ERROR] Administrator privileges required.
    echo.
    echo 请右键本文件，选择「以管理员身份运行」。
    echo 双击运行没有权限，窗口会停在这里，不会自动升级。
    echo.
    echo [%date% %time%] not admin>>"%LOG%"
    pause
    exit /b 1
)

echo Updating aria2-next and AriaNg...
echo 正在更新，请等待下载结束，不要关闭窗口。
echo Log: %LOG%
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%PS1%' -ErrorAction SilentlyContinue"

set "FORCEARG="
if /I "%~1"=="force" set "FORCEARG=-Force"
if /I "%~1"=="-Force" set "FORCEARG=-Force"

"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -NoPause %FORCEARG%
set "EXITCODE=%ERRORLEVEL%"

chcp 936 >nul

echo.
if not "%EXITCODE%"=="0" (
    echo Update failed, exit code %EXITCODE%.
    echo 更新失败。请把同目录 Update.log 的内容发出来以便排查。
) else (
    echo Done.
    echo 执行完毕。
)
echo.
pause
exit /b %EXITCODE%
