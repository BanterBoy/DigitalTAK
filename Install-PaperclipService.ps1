#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Migrates Paperclip from PM2 to a Windows Service via NSSM.

.DESCRIPTION
    Run once as Administrator. Performs the following:
      1. Kills the PM2-managed paperclip process and uninstalls PM2
      2. Removes PM2 data directories
      3. Locates or downloads NSSM (Non-Sucking Service Manager)
      4. Registers Paperclip as a Windows service with auto-start
      5. Starts the service

    After running, manage the service with standard Windows tools:
      sc start Paperclip    / sc stop Paperclip
      nssm status Paperclip / nssm edit Paperclip   (opens settings GUI)
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$ServiceName = 'Paperclip'
$WorkDir     = 'C:\Users\LukeLeigh\DigitalTAK'
$LogDir      = "$WorkDir\logs"
$ToolsDir    = "$WorkDir\tools"
$NssmExe     = "$ToolsDir\nssm.exe"

# ── 1. Stop and remove PM2 ────────────────────────────────────────────────────
Write-Host '1. Removing PM2 paperclip process...' -ForegroundColor Cyan

$pm2Cmd = Get-Command pm2 -ErrorAction SilentlyContinue
if ($pm2Cmd) {
    & pm2 stop paperclip   2>&1 | Out-Null
    & pm2 delete paperclip 2>&1 | Out-Null
    & pm2 kill             2>&1 | Out-Null
    Write-Host '   Uninstalling PM2 globally...' -ForegroundColor DarkGray
    & npm uninstall -g pm2 2>&1 | Out-Null
} else {
    Write-Host '   PM2 not found — skipping.' -ForegroundColor DarkGray
}

Write-Host '   Removing PM2 data directories...' -ForegroundColor DarkGray
@("$env:USERPROFILE\.pm2", "$env:APPDATA\pm2") | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Recurse -Force
        Write-Host "   Removed: $_" -ForegroundColor DarkGray
    }
}

# ── 2. Locate or download NSSM ────────────────────────────────────────────────
Write-Host '2. Locating NSSM...' -ForegroundColor Cyan

$nssmOnPath = Get-Command nssm -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if ($nssmOnPath) {
    $NssmExe = $nssmOnPath
    Write-Host "   Found on PATH: $NssmExe" -ForegroundColor DarkGray
} elseif (Test-Path $NssmExe) {
    Write-Host "   Found in tools/: $NssmExe" -ForegroundColor DarkGray
} else {
    Write-Host '   Downloading NSSM 2.24...' -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    $zip = Join-Path $env:TEMP 'nssm-2.24.zip'
    Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $zip -UseBasicParsing
    $extractDir = Join-Path $env:TEMP 'nssm-extract'
    Expand-Archive -Path $zip -DestinationPath $extractDir -Force
    Copy-Item (Join-Path $extractDir 'nssm-2.24\win64\nssm.exe') -Destination $NssmExe
    Remove-Item $zip, $extractDir -Recurse -Force
    Write-Host "   Saved to: $NssmExe" -ForegroundColor DarkGray
}

# ── 3. Remove existing service if present ─────────────────────────────────────
Write-Host "3. Checking for existing '$ServiceName' service..." -ForegroundColor Cyan
$existing = & sc.exe query $ServiceName 2>&1
if ($existing -match 'SERVICE_NAME') {
    Write-Host '   Removing existing service...' -ForegroundColor DarkGray
    & $NssmExe stop   $ServiceName 2>&1 | Out-Null
    & $NssmExe remove $ServiceName confirm
}

# ── 4. Create log directory ───────────────────────────────────────────────────
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# ── 5. Resolve Node.js location for PATH injection ────────────────────────────
Write-Host '4. Resolving Node.js location...' -ForegroundColor Cyan
$nodeExe  = Get-Command node -ErrorAction Stop
$nodePath = Split-Path $nodeExe.Source
Write-Host "   Node.js directory: $nodePath" -ForegroundColor DarkGray

# ── 6. Install the NSSM service ───────────────────────────────────────────────
Write-Host "5. Installing '$ServiceName' Windows service..." -ForegroundColor Cyan

& $NssmExe install $ServiceName 'C:\Windows\System32\cmd.exe'
& $NssmExe set $ServiceName AppParameters    '/c npx paperclipai run'
& $NssmExe set $ServiceName AppDirectory     $WorkDir
& $NssmExe set $ServiceName DisplayName      'Paperclip AI Service'
& $NssmExe set $ServiceName Description      'Paperclip AI agent runner (DigitalTAK)'
& $NssmExe set $ServiceName Start            SERVICE_AUTO_START
& $NssmExe set $ServiceName AppStdout        "$LogDir\paperclip-stdout.log"
& $NssmExe set $ServiceName AppStderr        "$LogDir\paperclip-stderr.log"
& $NssmExe set $ServiceName AppRotateFiles   1
& $NssmExe set $ServiceName AppRotateSeconds 86400
# Inject Node.js directory into PATH so npx resolves correctly when running as SYSTEM.
& $NssmExe set $ServiceName AppEnvironmentExtra "PATH=$nodePath;$env:PATH"

# ── 7. Start the service ──────────────────────────────────────────────────────
Write-Host "6. Starting '$ServiceName' service..." -ForegroundColor Cyan
& $NssmExe start $ServiceName
Start-Sleep -Seconds 4

$status = & sc.exe query $ServiceName
if ($status -match 'RUNNING') {
    Write-Host "[OK] $ServiceName service is running." -ForegroundColor Green
} else {
    Write-Warning "$ServiceName may not be running yet — inspect with: nssm status $ServiceName"
    Write-Host "     Logs: $LogDir" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Migration complete.' -ForegroundColor Green
Write-Host 'Service management:' -ForegroundColor DarkGray
Write-Host "  sc start $ServiceName" -ForegroundColor DarkGray
Write-Host "  sc stop $ServiceName" -ForegroundColor DarkGray
Write-Host "  nssm status $ServiceName" -ForegroundColor DarkGray
Write-Host "  nssm edit $ServiceName    (settings GUI)" -ForegroundColor DarkGray
