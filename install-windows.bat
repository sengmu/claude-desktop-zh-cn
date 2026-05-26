@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1

echo Staging installer to Windows local temp...
set "CLAUDE_ZH_STAGE=%TEMP%\ClaudeDesktopZhCnInstaller"
set "CLAUDE_ZH_SOURCE=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $src=$env:CLAUDE_ZH_SOURCE; $dst=$env:CLAUDE_ZH_STAGE; if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }; New-Item -ItemType Directory -Path $dst -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $src 'install-windows.bat') -Destination $dst -Force; Copy-Item -LiteralPath (Join-Path $src 'README.md') -Destination $dst -Force -ErrorAction SilentlyContinue; Copy-Item -LiteralPath (Join-Path $src 'scripts') -Destination $dst -Recurse -Force; Copy-Item -LiteralPath (Join-Path $src 'resources') -Destination $dst -Recurse -Force; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
    echo.
    echo Failed to copy installer files to local temp.
    echo Please copy the whole claude-desktop-zh-cn folder to a local Windows path, then run install-windows.bat again.
    pause
    exit /b 1
)

echo Requesting administrator privileges...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $script=Join-Path $env:CLAUDE_ZH_STAGE 'scripts\install_windows.ps1'; Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Interactive' -WorkingDirectory $env:CLAUDE_ZH_STAGE -Verb RunAs -ErrorAction Stop; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
    echo.
    echo Failed to request administrator privileges.
    echo If you cancelled UAC, run this script again.
    pause
    exit /b 1
)

exit /b 0
