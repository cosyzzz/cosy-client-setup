# Cosy Classroom System -- Universal Windows Client Installer (Mandatory Latest Edition)
# Compatible with Windows 7/8/10/11/Server (x64 & ARM64), PS 5.1+, PS 7+, irm | iex
[CmdletBinding()]
param(
    [string]$ServerUrl = "",
    [string]$Ticket = "",
    [string]$CertPin = "",
    [ValidateSet("auto", "github", "server")]
    [string]$Source = "auto",
    [switch]$Bg,
    [switch]$Fg,
    [switch]$Quiet,
    [switch]$Silent,
    [switch]$Force,
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$NoClose
)

$ErrorActionPreference = "Stop"

$RepoOwner = "cosyzzz"
$RepoName  = "cosy-client-setup"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"
$RelBase   = "https://github.com/$RepoOwner/$RepoName/releases/latest/download"
$DefaultServer = "https://sykids.dpdns.org"

# Read env overrides (supports `irm ... | iex` cleanly)
if (-not $ServerUrl) {
    if ($env:SYKIDS_SERVER) { $ServerUrl = $env:SYKIDS_SERVER }
    elseif ($env:CP_SERVER_URL) { $ServerUrl = $env:CP_SERVER_URL }
}
if (-not $Ticket) {
    if ($env:SYKIDS_TICKET) { $Ticket = $env:SYKIDS_TICKET }
    elseif ($env:CP_ENROLL_TICKET) { $Ticket = $env:CP_ENROLL_TICKET }
}
if (-not $CertPin -and $env:CP_CERT_PIN) { $CertPin = $env:CP_CERT_PIN }
if ($env:COSY_BG -eq "1") { $Bg = $true }
if ($env:COSY_FORCE -eq "1") { $Force = $true }
if ($env:COSY_QUIET -eq "1") { $Quiet = $true }
if ($env:COSY_VERIFY_ONLY -eq "1") { $VerifyOnly = $true }
if ($env:COSY_DRY_RUN -eq "1") { $DryRun = $true }
if ($env:COSY_SOURCE) { $Source = $env:COSY_SOURCE }
if ($Silent) { $Quiet = $true }

function Write-Log {
    param([string]$Msg, [string]$Color = "Gray")
    if (-not $Quiet) {
        Write-Host $Msg -ForegroundColor $Color
    }
}

# Force TLS 1.2+ across PowerShell 5.1 / .NET 4.x / Win7-Win11
try {
    $proto = [Net.SecurityProtocolType]::Tls12
    try { $proto = $proto -bor [Net.SecurityProtocolType]::Tls13 } catch {}
    [Net.ServicePointManager]::SecurityProtocol = $proto
} catch {
    try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}
}

# Configure system default proxy credentials if behind corporate proxy
try {
    $proxy = [System.Net.WebRequest]::DefaultWebProxy
    if ($proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    }
} catch {}

# Architecture check
$is64BitOS = [Environment]::Is64BitOperatingSystem
$arch = ($env:PROCESSOR_ARCHITECTURE + "").ToUpperInvariant()
if (-not $is64BitOS) {
    Write-Host "[ERROR] 32-bit (x86) Windows OS is not supported by x64 client binaries." -ForegroundColor Red
    exit 2
}

$CurlBin = $null
foreach ($cand in @((Join-Path $env:SystemRoot "System32\curl.exe"), "curl.exe")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $CurlBin = $cmd.Source; break }
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [int]$TimeoutSec = 180
    )
    $parent = Split-Path -Parent $OutFile
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    # Tier 1: Native curl.exe (fastest, TLS 1.2/1.3, HTTP/2, retry)
    if ($CurlBin) {
        try {
            & $CurlBin --retry 3 --retry-delay 2 -fsSL --connect-timeout 15 --max-time $TimeoutSec $Url -o $OutFile 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                return $true
            }
        } catch {}
    }

    # Tier 2: Invoke-WebRequest (PS 5.1+ / PS 7+)
    try {
        $iwrParams = @{
            Uri = $Url
            OutFile = $OutFile
            TimeoutSec = $TimeoutSec
            ErrorAction = "Stop"
        }
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $iwrParams["UseBasicParsing"] = $true
        }
        Invoke-WebRequest @iwrParams
        if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
            return $true
        }
    } catch {}

    # Tier 3: .NET WebClient (Win7 / PS 2-4 / legacy proxy compatible)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "CosyClientSetup/2.4")
        if ($env:HTTPS_PROXY) {
            $wc.Proxy = New-Object System.Net.WebProxy($env:HTTPS_PROXY, $true)
        }
        $wc.DownloadFile($Url, $OutFile)
        if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
            return $true
        }
    } catch {}

    # Tier 4: BITS Transfer
    try {
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                return $true
            }
        }
    } catch {}

    # Tier 5: certutil -urlcache fallback
    try {
        $certutil = Join-Path $env:SystemRoot "System32\certutil.exe"
        if (Test-Path $certutil) {
            & $certutil -urlcache -split -f $Url $OutFile >$null 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                return $true
            }
        }
    } catch {}

    return $false
}

function Invoke-DownloadString {
    param([string]$Url, [int]$TimeoutSec = 15)
    $tmp = Join-Path $env:TEMP ("cosy_str_" + [guid]::NewGuid().ToString("N").Substring(0,8) + ".tmp")
    try {
        if (Invoke-DownloadFile -Url $Url -OutFile $tmp -TimeoutSec $TimeoutSec) {
            return [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
        }
    } catch {}
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Get-FileSha256Lower {
    param([string]$Path)
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = $sha.ComputeHash($fs)
        return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $fs.Dispose()
        $sha.Dispose()
    }
}

function Compare-ClientVersion {
    param([string]$A, [string]$B)
    $pa = @($A -replace '[^0-9\.]', '' -split '\.' | Where-Object { $_ -ne '' })
    $pb = @($B -replace '[^0-9\.]', '' -split '\.' | Where-Object { $_ -ne '' })
    $max = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $va = if ($i -lt $pa.Count) { [int64]$pa[$i] } else { 0 }
        $vb = if ($i -lt $pb.Count) { [int64]$pb[$i] } else { 0 }
        if ($va -gt $vb) { return 1 }
        if ($va -lt $vb) { return -1 }
    }
    return 0
}

function Get-InstalledClientInfo {
    $info = @{ Installed = $false; Version = "0.0.0"; ServiceRunning = $false; ExePath = "" }
    foreach ($svcName in @("cpsv", "cp-svc", "ChildrenProtection")) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $info.Installed = $true
                if ($svc.Status -eq "Running") { $info.ServiceRunning = $true }
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
                if (Test-Path $regPath) {
                    $img = (Get-ItemProperty -Path $regPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
                    if ($img) {
                        $exe = ($img -replace '^"([^"]+)".*$', '$1' -split '\s+--')[0].Trim('"')
                        if (Test-Path -LiteralPath $exe) {
                            $info.ExePath = $exe
                            $ver = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
                            if ($ver) { $info.Version = ($ver.Trim() -replace '\s+', '') }
                        }
                    }
                }
                break
            }
        } catch {}
    }
    if (-not $info.Installed) {
        foreach ($cand in @(
            "$env:ProgramFiles\CosySystem\cp-st.exe",
            "$env:ProgramFiles\CosySystem\cpsv.exe",
            "$env:ProgramFiles\ChildrenProtection\ChildrenProtection.exe"
        )) {
            if (Test-Path -LiteralPath $cand) {
                $info.Installed = $true
                $info.ExePath = $cand
                $ver = (Get-Item -LiteralPath $cand).VersionInfo.FileVersion
                if ($ver) { $info.Version = ($ver.Trim() -replace '\s+', '') }
                break
            }
        }
    }
    return $info
}

# Identity & Elevation check
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin  = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSystem = $currentIdentity.Name -match "^(?i)NT AUTHORITY\\SYSTEM$"

# Handle -Bg (Session-0 SYSTEM detach)
if ($Bg -and (-not $VerifyOnly) -and (-not $DryRun)) {
    if (-not $isAdmin) {
        $selfPath = $PSCommandPath
        if (-not $selfPath -or -not (Test-Path -LiteralPath $selfPath)) {
            $selfPath = Join-Path $env:TEMP "cosy-win-setup.ps1"
            if (-not (Invoke-DownloadFile -Url "$RawBase/win.ps1" -OutFile $selfPath -TimeoutSec 30)) {
                Write-Host "[ERROR] Failed to stage win.ps1 for elevated launch." -ForegroundColor Red
                exit 1
            }
        }
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$selfPath`"", "-Bg")
        if ($ServerUrl) { $argList += @("-ServerUrl", "`"$ServerUrl`"") }
        if ($Ticket) { $argList += @("-Ticket", "`"$Ticket`"") }
        if ($CertPin) { $argList += @("-CertPin", "`"$CertPin`"") }
        if ($Force) { $argList += "-Force" }
        if ($Source -ne "auto") { $argList += @("-Source", $Source) }
        Start-Process powershell.exe -ArgumentList ($argList -join ' ') -Verb RunAs
        exit 0
    }

    if ($isAdmin -and (-not $isSystem)) {
        $sysTemp = Join-Path $env:SystemRoot "Temp"
        $bgWorkerCmd = Join-Path $sysTemp "cosy_bg_worker.cmd"
        $bgEnvCmd    = Join-Path $sysTemp "cosy_bg_env.cmd"
        if (Invoke-DownloadFile -Url "$RawBase/win.cmd" -OutFile $bgWorkerCmd -TimeoutSec 30) {
            $envLines = @(
                "set `"SERVER_URL=$ServerUrl`"",
                "set `"USE_TICKET=$Ticket`"",
                "set `"USE_CERT_PIN=$CertPin`"",
                "set `"FORCE_INSTALL=$(if ($Force) {'1'} else {'0'})`""
            )
            [System.IO.File]::WriteAllLines($bgEnvCmd, $envLines, [System.Text.Encoding]::ASCII)
            $schtasks = Join-Path $env:SystemRoot "System32\schtasks.exe"
            $tr = "`"$env:SystemRoot\System32\cmd.exe`" /d /c `"`"$bgWorkerCmd`" --bg-worker`""
            & $schtasks /Create /TN "CosySystemBootstrap" /RU "SYSTEM" /RL HIGHEST /SC ONCE /ST 00:00 /TR $tr /F >$null 2>&1
            & $schtasks /Run /TN "CosySystemBootstrap" >$null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "[OK] Background Session-0 installation dispatched (log: $sysTemp\cosy_bootstrap.log)." "Green"
                exit 0
            }
        }
    }
}

# Interactive UAC self-elevation if not admin and not VerifyOnly/DryRun
if ((-not $isAdmin) -and (-not $VerifyOnly) -and (-not $DryRun)) {
    Write-Log "[*] Administrator privilege required. Requesting UAC elevation..." "Yellow"
    $selfPath = $PSCommandPath
    if (-not $selfPath -or -not (Test-Path -LiteralPath $selfPath)) {
        $selfPath = Join-Path $env:TEMP "cosy-win-setup.ps1"
        if (-not (Invoke-DownloadFile -Url "$RawBase/win.ps1" -OutFile $selfPath -TimeoutSec 30)) {
            Write-Host "[ERROR] Failed to download installer script for elevation." -ForegroundColor Red
            exit 1
        }
    }
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = "powershell.exe" }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$selfPath`"")
    if ($ServerUrl) { $argList += @("-ServerUrl", "`"$ServerUrl`"") }
    if ($Ticket) { $argList += @("-Ticket", "`"$Ticket`"") }
    if ($CertPin) { $argList += @("-CertPin", "`"$CertPin`"") }
    if ($Force) { $argList += "-Force" }
    if ($Quiet) { $argList += "-Quiet" }
    if ($NoClose) { $argList += "-NoClose" }
    if ($Source -ne "auto") { $argList += @("-Source", $Source) }
    $proc = Start-Process -FilePath $psExe -ArgumentList ($argList -join ' ') -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

Write-Log "============================================================================" "Cyan"
Write-Log "  Cosy Classroom System — Universal Windows Installer ($arch)" "Cyan"
Write-Log "============================================================================" "Cyan"

# [1/5] Resolve Server URL
Write-Log "[1/5] Resolving server endpoint..." "Gray"
if (-not $ServerUrl) {
    $beaconRaw = Invoke-DownloadString -Url "$RawBase/beacon.txt" -TimeoutSec 10
    if ($beaconRaw) {
        $parts = $beaconRaw.Trim().Split('|')
        if ($parts.Length -ge 2 -and $parts[0] -eq "SYKIDS-BEACON-V2" -and $parts[1]) {
            $cand = $parts[1] -replace '^wss://', 'https://' -replace '^ws://', 'http://' -replace '/ws$', ''
            $ServerUrl = $cand
            if (-not $CertPin -and $parts.Length -ge 3 -and $parts[2]) {
                $CertPin = $parts[2]
            }
        }
    }
}
if (-not $ServerUrl) { $ServerUrl = $DefaultServer }
$ServerUrl = $ServerUrl.TrimEnd('/')
$WsUrl = ($ServerUrl -replace '^https://', 'wss://' -replace '^http://', 'ws://') + "/ws"
if (-not $CertPin) { $CertPin = "SYSTEM_CA" }
Write-Log "      Server: $ServerUrl ($WsUrl)" "DarkGray"

# [2/5] Resolve STRICTLY LATEST client version metadata (GitHub Release vs Server)
Write-Log "[2/5] Checking latest available client version..." "Gray"
$ghMeta = $null
$srvMeta = $null

if ($Source -ne "server") {
    $ghJson = Invoke-DownloadString -Url "$RawBase/version.json" -TimeoutSec 12
    if (-not $ghJson) { $ghJson = Invoke-DownloadString -Url "$RelBase/version.json" -TimeoutSec 12 }
    if ($ghJson) {
        try { $ghMeta = $ghJson | ConvertFrom-Json } catch {}
    }
}

if ($Source -ne "github") {
    $srvJson = Invoke-DownloadString -Url "$ServerUrl/update?client&check=1" -TimeoutSec 8
    if ($srvJson) {
        try { $srvMeta = $srvJson | ConvertFrom-Json } catch {}
    }
}

$chosenUrl = ""
$chosenSha = ""
$chosenVer = "0.0.0"
$chosenTag = ""

if ($ghMeta -and $ghMeta.windows) {
    $ghVer = [string]$ghMeta.version
    $ghSha = ([string]$ghMeta.windows.cpinstall_sha256).ToLowerInvariant()
    $ghUrl = [string]$ghMeta.windows.cpinstall_url
    if (-not $ghUrl) { $ghUrl = "$RelBase/CPInstall.exe" }
    $chosenUrl = $ghUrl
    $chosenSha = $ghSha
    $chosenVer = $ghVer
    $chosenTag = "GitHub Release ($ghVer)"
}

if ($srvMeta -and $srvMeta.available) {
    $sVer = [string]$srvMeta.version
    $sSha = ([string]$srvMeta.sha256).ToLowerInvariant()
    $sUrl = [string]$srvMeta.url
    if (-not $sUrl) { $sUrl = "$ServerUrl/update?client&dl=1&tier=sysoftware" }
    if ($srvMeta.cert_pin -and $CertPin -eq "SYSTEM_CA") {
        $CertPin = [string]$srvMeta.cert_pin
    }
    if (-not $chosenUrl -or (Compare-ClientVersion $sVer $chosenVer) -gt 0) {
        $chosenUrl = $sUrl
        $chosenSha = $sSha
        $chosenVer = $sVer
        $chosenTag = "Live Server ($sVer)"
    }
}

if (-not $chosenUrl) {
    # Emergency direct release fallback
    $chosenUrl = "$RelBase/CPInstall.exe"
    $chosenTag = "GitHub Release (direct fallback)"
}

Write-Log "      Selected Latest Build: $chosenTag" "Green"

# [3/5] Check currently installed version & enforce mandatory latest
$installed = Get-InstalledClientInfo
Write-Log "[3/5] Local state: Installed=$($installed.Installed), Version=$($installed.Version), Running=$($installed.ServiceRunning)" "Gray"

if ((-not $Force) -and (-not $VerifyOnly) -and (-not $DryRun) -and $installed.Installed -and $installed.ServiceRunning -and $chosenVer -ne "0.0.0") {
    $cmp = Compare-ClientVersion $installed.Version $chosenVer
    if ($cmp -ge 0) {
        Write-Log "[OK] Machine already has the latest client ($($installed.Version)) running. Use -Force to reinstall." "Green"
        exit 0
    } else {
        Write-Log "[UPGRADE] Older version detected ($($installed.Version) -> $chosenVer). Mandatory upgrade starting..." "Yellow"
    }
}

if ($DryRun) {
    Write-Log "[DRY-RUN] Would download $chosenUrl (expected SHA256: $chosenSha) and install version $chosenVer for $WsUrl." "Cyan"
    exit 0
}

# [4/5] Download & Verify SHA-256
$workDir = Join-Path $env:TEMP ("cosy_work_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$exePath = Join-Path $workDir "CPInstall.exe"

try {
    Write-Log "[4/5] Downloading CPInstall.exe ($chosenTag)..." "Gray"
    $ok = Invoke-DownloadFile -Url $chosenUrl -OutFile $exePath -TimeoutSec 240
    if (-not $ok -and $chosenUrl -ne "$RelBase/CPInstall.exe") {
        Write-Log "      Primary source failed, falling back to GitHub Release latest..." "Yellow"
        $chosenUrl = "$RelBase/CPInstall.exe"
        if ($ghMeta -and $ghMeta.windows) { $chosenSha = ([string]$ghMeta.windows.cpinstall_sha256).ToLowerInvariant() }
        $ok = Invoke-DownloadFile -Url $chosenUrl -OutFile $exePath -TimeoutSec 240
    }
    if (-not $ok) {
        Write-Host "[ERROR] Unable to download CPInstall.exe from any source." -ForegroundColor Red
        exit 1
    }

    $actualSha = Get-FileSha256Lower -Path $exePath
    if ($chosenSha -and ($actualSha -ne $chosenSha)) {
        Write-Host "[ERROR] SHA-256 verification failed! Expected: $chosenSha, Actual: $actualSha" -ForegroundColor Red
        exit 1
    }
    Write-Log "      SHA-256 verified: $($actualSha.Substring(0, 16))..." "Green"

    if ($VerifyOnly) {
        Write-Log "[5/5] Running CPInstall.exe --selftest..." "Gray"
        $p = Start-Process -FilePath $exePath -ArgumentList "--selftest" -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Host "[ERROR] --selftest failed with exit code $($p.ExitCode)" -ForegroundColor Red
            exit $p.ExitCode
        }
        Write-Log "[OK] E2E verification passed (Latest=$chosenVer, SHA256 OK, --selftest OK)." "Green"
        exit 0
    }

    # [5/5] Install / Force Upgrade via CPInstall.exe
    Write-Log "[5/5] Installing/upgrading Cosy Client services (v$chosenVer)..." "Gray"
    $env:CP_WS_URL = $WsUrl
    $env:CP_CERT_PIN = $CertPin
    if ($Ticket) { $env:CP_ENROLL_TICKET = $Ticket }

    $instArgs = "--install-auto --ws-url `"$WsUrl`" --cert-pin `"$CertPin`""
    if ($Ticket) { $instArgs += " --ticket `"$Ticket`"" }
    if ($chosenVer -and $chosenVer -ne "0.0.0") { $instArgs += " --client-version `"$chosenVer`"" }
    if ($actualSha) { $instArgs += " --installer-sha256 `"$actualSha`"" }

    $proc = Start-Process -FilePath $exePath -ArgumentList $instArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "[ERROR] CPInstall.exe failed with exit code $($proc.ExitCode)" -ForegroundColor Red
        exit $proc.ExitCode
    }

    # Confirm service health
    $svcOk = $false
    for ($i = 0; $i -lt 6; $i++) {
        $svc = Get-Service -Name "cpsv" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            $svcOk = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if ($svcOk) {
        Write-Log "[OK] Cosy System v$chosenVer installed and running (cpsv / cpwg / cp-ag)." "Green"
        Write-Log "     Dashboard: $ServerUrl/" "Cyan"
    } else {
        Write-Log "[WARN] Installer completed (exit 0) — verify service with: sc.exe query cpsv" "Yellow"
    }
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
