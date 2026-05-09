@echo off
chcp 65001 >nul 2>&1

if "%CLAUDE_ZH_ELEVATED%"=="1" goto elevated

echo Requesting administrator privileges...
set "CLAUDE_ZH_DIR=%~dp0"
set "CLAUDE_ZH_BAT=%~nx0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $q=[char]34; $dir=$env:CLAUDE_ZH_DIR; $bat=$env:CLAUDE_ZH_BAT; $cmd='/k set ' + $q + 'CLAUDE_ZH_ELEVATED=1' + $q + ' && pushd ' + $q + $dir + $q + ' && call ' + $q + $bat + $q; Start-Process -FilePath 'cmd.exe' -ArgumentList $cmd -Verb RunAs -ErrorAction Stop; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
    echo.
    echo Failed to request administrator privileges.
    echo If you cancelled UAC, please run this script again.
    echo.
    pause
    exit /b 1
)
exit /b

:elevated
set "CLAUDE_ZH_ELEVATED="

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo Failed to obtain administrator privileges.
    echo Please right-click this file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

echo.
echo === Claude Desktop Windows 中文补丁 ===
echo.
echo [1] 安装简体中文
echo [2] 安装繁体中文（台湾）
echo [3] 安装繁体中文（香港）
echo [4] 恢复原样 / 卸载补丁
echo [Q] 退出
echo.
choice /C 1234Q /N /M "请选择操作 [1/2/3/4/Q]: "

if errorlevel 5 exit /b 0
if errorlevel 4 goto uninstall
if errorlevel 3 set LANGUAGE=zh-HK& goto install
if errorlevel 2 set LANGUAGE=zh-TW& goto install
set LANGUAGE=zh-CN

:install
set ACTION=install
goto run

:uninstall
set ACTION=uninstall
set LANGUAGE=zh-CN

:run

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_windows.ps1" %ACTION% %LANGUAGE%
set EXITCODE=%ERRORLEVEL%

echo.
pause
exit /b %EXITCODE%
