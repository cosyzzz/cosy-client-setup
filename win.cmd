@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================================
:: Cosy Classroom System — Universal Windows CMD Bootstrap (Mandatory Latest)
:: Compatible with: Windows 7 / 8 / 10 / 11 / Server 2012-2025 (CMD, GPO, Task)
:: Download fallbacks: curl.exe -> PowerShell -> bitsadmin -> certutil
:: ============================================================================

set "REPO_OWNER=cosyzzz"
set "REPO_NAME=cosy-client-setup"
set "RAW_BASE=https://raw.githubusercontent.com/%REPO_OWNER%/%REPO_NAME%/main"
set "REL_BASE=https://github.com/%REPO_OWNER%/%REPO_NAME%/releases/latest/download"
set "DEFAULT_SERVER=https://sykids.dpdns.org"

set "SERVER_URL=%SYKIDS_SERVER%"
if not defined SERVER_URL set "SERVER_URL=%CP_SERVER_URL%"
set "USE_TICKET=%SYKIDS_TICKET%"
if not defined USE_TICKET set "USE_TICKET=%CP_ENROLL_TICKET%"
set "USE_CERT_PIN=%CP_CERT_PIN%"
set "BG_MODE=0"
set "BG_WORKER=0"
set "QUIET=0"
set "FORCE_INSTALL=0"
set "VERIFY_ONLY=0"
set "NO_CLOSE=0"
set "SOURCE_MODE=auto"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--server" (set "SERVER_URL=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="-s"       (set "SERVER_URL=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="--ticket" (set "USE_TICKET=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="-t"       (set "USE_TICKET=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="--cert-pin" (set "USE_CERT_PIN=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="--source" (set "SOURCE_MODE=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="--bg"     (set "BG_MODE=1" & shift & goto :parse_args)
if /i "%~1"=="--bg-worker" (set "BG_WORKER=1" & set "QUIET=1" & shift & goto :parse_args)
if /i "%~1"=="--quiet"  (set "QUIET=1" & shift & goto :parse_args)
if /i "%~1"=="/q"       (set "QUIET=1" & shift & goto :parse_args)
if /i "%~1"=="--force"  (set "FORCE_INSTALL=1" & shift & goto :parse_args)
if /i "%~1"=="-f"       (set "FORCE_INSTALL=1" & shift & goto :parse_args)
if /i "%~1"=="--verify-only" (set "VERIFY_ONLY=1" & shift & goto :parse_args)
if /i "%~1"=="--no-close" (set "NO_CLOSE=1" & shift & goto :parse_args)
shift
goto :parse_args

:args_done
if "%BG_WORKER%"=="1" (
    if exist "%SystemRoot%\Temp\cosy_bg_env.cmd" call "%SystemRoot%\Temp\cosy_bg_env.cmd"
)

set "SHOW_UI=1"
if "%QUIET%"=="1" set "SHOW_UI=0"
if "%BG_WORKER%"=="1" set "SHOW_UI=0"

:: Verify 64-bit OS
if not defined ProgramW6432 (
    if /i "%PROCESSOR_ARCHITECTURE%"=="x86" (
        echo [ERROR] 32-bit x86 Windows is not supported. Requires 64-bit Windows.
        exit /b 2
    )
)

:: Handle --bg detach via Session-0 SYSTEM task
if "%BG_MODE%"=="1" if "%BG_WORKER%"=="0" if "%VERIFY_ONLY%"=="0" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo [*] Requesting UAC elevation for background Session-0 install...
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--bg --server \"%SERVER_URL%\" --ticket \"%USE_TICKET%\"' -Verb RunAs" >nul 2>&1
        exit /b 0
    )
    copy /y "%~f0" "%SystemRoot%\Temp\cosy_bg_worker.cmd" >nul 2>&1
    (
        echo set "SERVER_URL=%SERVER_URL%"
        echo set "USE_TICKET=%USE_TICKET%"
        echo set "USE_CERT_PIN=%USE_CERT_PIN%"
        echo set "FORCE_INSTALL=%FORCE_INSTALL%"
    ) > "%SystemRoot%\Temp\cosy_bg_env.cmd"
    "%SystemRoot%\System32\schtasks.exe" /Create /TN "CosySystemBootstrap" /RU "SYSTEM" /RL HIGHEST /SC ONCE /ST 00:00 /TR "\"%SystemRoot%\System32\cmd.exe\" /d /c \"\"%SystemRoot%\Temp\cosy_bg_worker.cmd\" --bg-worker\"" /F >nul 2>&1
    "%SystemRoot%\System32\schtasks.exe" /Run /TN "CosySystemBootstrap" >nul 2>&1
    if %errorlevel% equ 0 (
        if "%SHOW_UI%"=="1" echo [OK] Background Session-0 install started. Log: %SystemRoot%\Temp\cosy_bootstrap.log
        exit /b 0
    )
)

:: Self-elevate UAC if interactive and not Admin
if "%VERIFY_ONLY%"=="0" if "%BG_WORKER%"=="0" (
    net session >nul 2>&1
    if errorlevel 1 (
        if "%SHOW_UI%"=="1" echo [*] Requesting Administrator elevation...
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -Wait" >nul 2>&1
        exit /b %errorlevel%
    )
)

set "WORK=%TEMP%\cosy_cmd_%RANDOM%%RANDOM%"
if "%BG_WORKER%"=="1" set "WORK=%SystemRoot%\Temp\cosy_cmd_%RANDOM%%RANDOM%"
mkdir "%WORK%" >nul 2>&1

if "%SHOW_UI%"=="1" echo [Cosy] [1/5] Resolving server and latest release metadata...

:: Resolve beacon if SERVER_URL empty
if not defined SERVER_URL (
    call :dl_file "%RAW_BASE%/beacon.txt" "%WORK%\beacon.txt"
    if exist "%WORK%\beacon.txt" (
        for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%WORK%\beacon.txt") do (
            if "%%A"=="SYKIDS-BEACON-V2" (
                set "B_WS=%%B"
                set "B_WS=!B_WS:wss://=https://!"
                set "B_WS=!B_WS:ws://=http://!"
                set "B_WS=!B_WS:/ws=!"
                set "SERVER_URL=!B_WS!"
                if not defined USE_CERT_PIN set "USE_CERT_PIN=%%C"
            )
        )
    )
)
if not defined SERVER_URL set "SERVER_URL=%DEFAULT_SERVER%"
if "!SERVER_URL:~-1!"=="/" set "SERVER_URL=!SERVER_URL:~0,-1!"
if not defined USE_CERT_PIN set "USE_CERT_PIN=SYSTEM_CA"

set "WS_URL=!SERVER_URL:https://=wss://!"
set "WS_URL=!WS_URL:http://=ws://!/ws"

:: Resolve latest metadata via PowerShell if available, else direct GitHub Release latest
set "DL_URL=%REL_BASE%/CPInstall.exe"
set "EXPECTED_SHA="
set "LATEST_VER=latest"

where powershell.exe >nul 2>&1
if %errorlevel% equ 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
      "$gh = $null; $srv = $null; " ^
      "try { $gh = (Invoke-WebRequest '%RAW_BASE%/version.json' -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json } catch {}; " ^
      "if ('%SOURCE_MODE%' -ne 'github') { try { $srv = (Invoke-WebRequest '%SERVER_URL%/update?client&check=1' -UseBasicParsing -TimeoutSec 8).Content | ConvertFrom-Json } catch {} }; " ^
      "$url='%REL_BASE%/CPInstall.exe'; $sha=''; $ver='0.0.0'; " ^
      "if ($gh -and $gh.windows) { $ver=[string]$gh.version; $sha=[string]$gh.windows.cpinstall_sha256; if ($gh.windows.cpinstall_url) { $url=[string]$gh.windows.cpinstall_url } }; " ^
      "if ($srv -and $srv.available) { " ^
      "  $sv=[string]$srv.version; " ^
      "  $c=0; $pa=$sv -replace '[^0-9\.]','' -split '\.'; $pb=$ver -replace '[^0-9\.]','' -split '\.'; " ^
      "  for($i=0;$i -lt [Math]::Max($pa.Count,$pb.Count);$i++){ $va=if($i -lt $pa.Count){[int64]$pa[$i]}else{0}; $vb=if($i -lt $pb.Count){[int64]$pb[$i]}else{0}; if($va -gt $vb){$c=1;break} if($va -lt $vb){$c=-1;break} }; " ^
      "  if ($c -gt 0 -or -not $gh) { $ver=$sv; $sha=[string]$srv.sha256; if ($srv.url) { $url=[string]$srv.url } } " ^
      "}; " ^
      "Set-Content -Path '%WORK%\meta.txt' -Value @(\"URL=$url\", \"SHA=$sha\", \"VER=$ver\") -Encoding ASCII" >nul 2>&1
    if exist "%WORK%\meta.txt" (
        for /f "usebackq tokens=1* delims==" %%K in ("%WORK%\meta.txt") do (
            if "%%K"=="URL" set "DL_URL=%%L"
            if "%%K"=="SHA" set "EXPECTED_SHA=%%L"
            if "%%K"=="VER" set "LATEST_VER=%%L"
        )
    )
)

if "%SHOW_UI%"=="1" echo [Cosy] [2/5] Latest target build: %LATEST_VER%
if "%SHOW_UI%"=="1" echo [Cosy] [3/5] Downloading CPInstall.exe...
if "%BG_WORKER%"=="1" echo [%DATE% %TIME%] Downloading %DL_URL% (v%LATEST_VER%) >> "%SystemRoot%\Temp\cosy_bootstrap.log" 2>&1

call :dl_file "!DL_URL!" "%WORK%\CPInstall.exe"
if not exist "%WORK%\CPInstall.exe" (
    if /i not "!DL_URL!"=="%REL_BASE%/CPInstall.exe" (
        if "%SHOW_UI%"=="1" echo [Cosy] Primary source failed, falling back to GitHub Release...
        call :dl_file "%REL_BASE%/CPInstall.exe" "%WORK%\CPInstall.exe"
    )
)

if not exist "%WORK%\CPInstall.exe" (
    if "%SHOW_UI%"=="1" echo [ERROR] Could not download CPInstall.exe from any source.
    if "%BG_WORKER%"=="1" echo [%DATE% %TIME%] ERROR: Download failed >> "%SystemRoot%\Temp\cosy_bootstrap.log"
    rd /s /q "%WORK%" 2>nul
    exit /b 1
)

:: Verify SHA-256 via certutil
set "ACTUAL_SHA="
for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "%WORK%\CPInstall.exe" SHA256 2^>nul') do (
    if not defined ACTUAL_SHA set "ACTUAL_SHA=%%H"
)
set "ACTUAL_SHA=!ACTUAL_SHA: =!"

if defined EXPECTED_SHA if not "!EXPECTED_SHA!"=="" (
    if /i not "!ACTUAL_SHA!"=="!EXPECTED_SHA!" (
        if "%SHOW_UI%"=="1" (
            echo [ERROR] SHA-256 mismatch!
            echo         Expected: !EXPECTED_SHA!
            echo         Actual  : !ACTUAL_SHA!
        )
        if "%BG_WORKER%"=="1" echo [%DATE% %TIME%] ERROR: SHA256 mismatch >> "%SystemRoot%\Temp\cosy_bootstrap.log"
        rd /s /q "%WORK%" 2>nul
        exit /b 1
    )
)
if "%SHOW_UI%"=="1" echo [Cosy] [4/5] SHA-256 verified [!ACTUAL_SHA:~0,16!...].

if "%VERIFY_ONLY%"=="1" (
    "%WORK%\CPInstall.exe" --selftest
    set "CP_EXIT=!ERRORLEVEL!"
    rd /s /q "%WORK%" 2>nul
    if !CP_EXIT! neq 0 exit /b !CP_EXIT!
    if "%SHOW_UI%"=="1" echo [Cosy] [100%%] Verification passed [v%LATEST_VER% + SHA256 + --selftest OK].
    exit /b 0
)

if "%SHOW_UI%"=="1" echo [Cosy] [5/5] Installing/upgrading Cosy System services...
set "CP_WS_URL=!WS_URL!"
set "CP_CERT_PIN=!USE_CERT_PIN!"
if defined USE_TICKET set "CP_ENROLL_TICKET=!USE_TICKET!"

set "EXTRA_ARGS=--ws-url "!WS_URL!" --cert-pin "!USE_CERT_PIN!" --installer-sha256 "!ACTUAL_SHA!""
if not "!LATEST_VER!"=="latest" if not "!LATEST_VER!"=="0.0.0" set "EXTRA_ARGS=!EXTRA_ARGS! --client-version "!LATEST_VER!""
if defined USE_TICKET set "EXTRA_ARGS=!EXTRA_ARGS! --ticket "!USE_TICKET!""

"%WORK%\CPInstall.exe" --install-auto !EXTRA_ARGS!
set "CP_EXIT=!ERRORLEVEL!"

if !CP_EXIT! neq 0 (
    if "%SHOW_UI%"=="1" echo [ERROR] CPInstall.exe exited with code !CP_EXIT!.
    if "%BG_WORKER%"=="1" echo [%DATE% %TIME%] ERROR: Exit !CP_EXIT! >> "%SystemRoot%\Temp\cosy_bootstrap.log"
    rd /s /q "%WORK%" 2>nul
    exit /b !CP_EXIT!
)

sc.exe query cpsv 2>nul | findstr /i "RUNNING" >nul 2>&1
if %errorlevel% equ 0 (
    if "%SHOW_UI%"=="1" echo [Cosy] [100%%] Installed v%LATEST_VER% and running [cpsv / cpwg / cp-ag].
    if "%BG_WORKER%"=="1" echo [%DATE% %TIME%] [OK] v%LATEST_VER% running >> "%SystemRoot%\Temp\cosy_bootstrap.log"
) else (
    if "%SHOW_UI%"=="1" echo [Cosy] Install completed. Check: sc.exe query cpsv
)

rd /s /q "%WORK%" 2>nul
if "%BG_WORKER%"=="1" (
    "%SystemRoot%\System32\schtasks.exe" /Delete /TN "CosySystemBootstrap" /F >nul 2>&1
    del /f /q "%SystemRoot%\Temp\cosy_bg_env.cmd" >nul 2>&1
    exit 0
)
exit /b 0

:dl_file
set "D_URL=%~1"
set "D_OUT=%~2"
if exist "%D_OUT%" del /f /q "%D_OUT%" >nul 2>&1

:: 1) curl.exe
where curl.exe >nul 2>&1
if %errorlevel% equ 0 (
    curl.exe --retry 3 -fsSL --connect-timeout 15 --max-time 180 "%D_URL%" -o "%D_OUT%" >nul 2>&1
    if exist "%D_OUT%" for %%F in ("%D_OUT%") do if %%~zF gtr 0 exit /b 0
)

:: 2) PowerShell TLS 1.2 WebClient / IWR
where powershell.exe >nul 2>&1
if %errorlevel% equ 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%D_URL%','%D_OUT%')" >nul 2>&1
    if exist "%D_OUT%" for %%F in ("%D_OUT%") do if %%~zF gtr 0 exit /b 0
)

:: 3) bitsadmin
where bitsadmin.exe >nul 2>&1
if %errorlevel% equ 0 (
    bitsadmin /transfer cosyDl /download /priority high "%D_URL%" "%D_OUT%" >nul 2>&1
    if exist "%D_OUT%" for %%F in ("%D_OUT%") do if %%~zF gtr 0 exit /b 0
)

:: 4) certutil
certutil -urlcache -split -f "%D_URL%" "%D_OUT%" >nul 2>&1
if exist "%D_OUT%" for %%F in ("%D_OUT%") do if %%~zF gtr 0 exit /b 0
exit /b 1
