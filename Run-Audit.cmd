@echo off
rem ============================================================================
rem  License & OneDrive Waste Finder - Windows launcher
rem
rem  Double-click this file to run the audit. It starts PowerShell 7 with the
rem  execution policy bypassed for this single run, so a freshly downloaded
rem  script is not blocked, and it works from wherever this folder lives.
rem
rem  If PowerShell 7 is not installed, it offers to install it for you.
rem
rem  You can also pass arguments from a command prompt, for example:
rem     Run-Audit.cmd -TenantId contoso.onmicrosoft.com
rem     Run-Audit.cmd -IncludeInactiveEnabled
rem ============================================================================
setlocal EnableExtensions

rem --- 1. Locate PowerShell 7: on PATH, or at its standard install location. ---
set "PWSH="
for /f "delims=" %%P in ('where pwsh 2^>nul') do set "PWSH=%%P"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if defined PWSH goto :run

rem --- 2. PowerShell 7 not found: offer to install it. ---
echo.
echo PowerShell 7 is required to run this audit, and was not found on this machine.
set /p "INSTALL=Install the latest PowerShell 7 now using winget? (Y/N): "
if /I not "%INSTALL%"=="Y" (
    echo.
    echo Skipped. You can install it later from https://aka.ms/powershell
    echo then run this file again.
    echo.
    pause
    exit /b 1
)

where winget >nul 2>nul
if errorlevel 1 (
    echo.
    echo winget is not available on this machine. Please install PowerShell 7
    echo manually from https://aka.ms/powershell then run this file again.
    echo.
    pause
    exit /b 1
)

echo.
echo Installing PowerShell 7, please wait...
winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements

rem --- 3. Pick up the freshly installed pwsh (PATH is not refreshed in this session). ---
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PWSH (
    echo.
    echo PowerShell 7 has been installed. Please run Run-Audit.cmd again to start the audit.
    echo.
    pause
    exit /b 0
)

:run
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Audit.ps1" %*

echo.
pause
