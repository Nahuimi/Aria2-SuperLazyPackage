@echo off

REM 设置编码格式为 UTF-8
chcp 65001 >nul

REM 检查是否以管理员身份运行
fltmc >nul 2>&1 || (
    echo 请以管理员身份运行此脚本！
    pause >nul
    exit /b
)

REM 定义脚本所在目录
set CURRENT_DIR=%~dp0

echo 正在更新 aria2-next 与 AriaNg ...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CURRENT_DIR%Update.ps1" -NoPause
set EXITCODE=%ERRORLEVEL%

echo.
if not "%EXITCODE%"=="0" (
    echo 更新失败，退出码 %EXITCODE%。
) else (
    echo 执行完毕。
)
echo 按任意键退出...
pause >nul
exit /b %EXITCODE%
