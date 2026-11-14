@echo off
setlocal EnableExtensions
title Cosy Classroom System — One-Click Client Installer

:: Auto-elevate UAC when double-clicked
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" >nul 2>&1
    exit /b
)

set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%win.cmd" (
    call "%SCRIPT_DIR%win.cmd" %*
    set "RC=%ERRORLEVEL%"
) else (
    set "TMP_CMD=%TEMP%\cosy_win_%RANDOM%.cmd"
    where curl.exe >nul 2>&1 && (
        curl.exe --retry 3 -fsSL "https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.cmd" -o "%TMP_CMD%"
    ) || (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/win.cmd','%TMP_CMD%')"
    )
    call "%TMP_CMD%" %*
    set "RC=%ERRORLEVEL%"
    del /f /q "%TMP_CMD%" >nul 2>&1
)

echo.
if %RC% equ 0 (
    echo [DONE] Client installation/update succeeded.
) else (
    echo [FAILED] Installer exited with code %RC%.
)
if "%~1"=="" pause
exit /b %RC%
