#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Migrates Paperclip from PM2 to a Windows Service via NSSM.

.DESCRIPTION
    Run once as Administrator. Performs the following:
      1. Kills the PM2-managed paperclip process and uninstalls PM2
      2. Removes PM2 data directories
      3. Locates or downloads NSSM (Non-Sucking Service Manager)
      4. Registers Paperclip as a Windows service running as the current user
      5. Starts the service

    The service runs as YOUR user account (not LocalSystem) so it can access
    your Paperclip config at ~/.paperclip. You will be prompted for your
    Windows password during installation.

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
    Write-Host '   Downloading NSSM 2.25...' -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    $zip = Join-Path $env:TEMP 'nssm-2.25.zip'
    Invoke-WebRequest -Uri 'https://github.com/dkxce/NSSM/releases/download/v2.25/NSSM_v2.25.zip' -OutFile $zip -UseBasicParsing
    $extractDir = Join-Path $env:TEMP 'nssm-extract'
    Expand-Archive -Path $zip -DestinationPath $extractDir -Force
    Copy-Item (Join-Path $extractDir 'win64\nssm.exe') -Destination $NssmExe
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

# ── 5. Verify Node.js and install paperclipai globally ─────────────────────────
Write-Host '4. Verifying Node.js and installing paperclipai...' -ForegroundColor Cyan
$nodeExe = Get-Command node -ErrorAction Stop
Write-Host "   Node.js: $($nodeExe.Source)" -ForegroundColor DarkGray

# Install/update paperclipai globally so the service can invoke it without npx.
# npx downloads on every run and prompts in non-interactive service contexts.
Write-Host '   Installing paperclipai globally...' -ForegroundColor DarkGray
& npm install -g paperclipai 2>&1 | Out-Null
$paperclipCmd = Get-Command paperclipai -ErrorAction SilentlyContinue
if (-not $paperclipCmd) {
    throw 'npm install -g paperclipai succeeded but the command is not on PATH. Check npm prefix -g.'
}
$PaperclipBin = $paperclipCmd.Source
Write-Host "   paperclipai: $PaperclipBin" -ForegroundColor DarkGray

# ── 6. Get credentials for service account ────────────────────────────────────
Write-Host '5. Service account setup...' -ForegroundColor Cyan
Write-Host "   The service must run as your user account to access ~/.paperclip config." -ForegroundColor DarkGray
Write-Host "   Enter your Windows password when prompted." -ForegroundColor DarkGray
$cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message 'Enter your Windows password for the Paperclip service'

# ── 7. Install the NSSM service ───────────────────────────────────────────────
Write-Host "6. Installing '$ServiceName' Windows service..." -ForegroundColor Cyan

# Use node.exe running the global paperclipai entry point directly.
# Avoids cmd.exe wrapper (Terminate batch job prompt) and npx (install prompt in non-interactive context).
$nodePath   = $nodeExe.Source
$entryPoint = Join-Path (Split-Path $PaperclipBin) 'node_modules\paperclipai\dist\index.js'
if (-not (Test-Path $entryPoint)) {
    # Fallback: the global bin is a .cmd shim; use the npm prefix to find the package
    $npmPrefix  = (& npm prefix -g).Trim()
    $entryPoint = Join-Path $npmPrefix 'node_modules\paperclipai\dist\index.js'
}
if (-not (Test-Path $entryPoint)) {
    throw "Cannot locate paperclipai entry point. Expected at: $entryPoint"
}

& $NssmExe install $ServiceName $nodePath
& $NssmExe set $ServiceName AppParameters    "`"$entryPoint`" run"
& $NssmExe set $ServiceName AppDirectory     $WorkDir
& $NssmExe set $ServiceName DisplayName      'Paperclip AI Service'
& $NssmExe set $ServiceName Description      'Paperclip AI agent runner (DigitalTAK)'
& $NssmExe set $ServiceName Start            SERVICE_AUTO_START
& $NssmExe set $ServiceName AppStdout        "$LogDir\paperclip-stdout.log"
& $NssmExe set $ServiceName AppStderr        "$LogDir\paperclip-stderr.log"
& $NssmExe set $ServiceName AppRotateFiles   1
& $NssmExe set $ServiceName AppRotateSeconds 86400

# Inject Node.js and npm global bin directories into the service PATH so any
# child processes (e.g. claude-code spawned by paperclipai) can resolve node/npm.
$nodeDir    = Split-Path $nodePath
$npmGlobBin = (& npm prefix -g).Trim()
& $NssmExe set $ServiceName AppEnvironmentExtra "PATH=$nodeDir;$npmGlobBin;$env:PATH"

# Run as the current user so the service can access ~/.paperclip config and npm cache.
& $NssmExe set $ServiceName ObjectName $cred.UserName $cred.GetNetworkCredential().Password
Write-Host "   Service will run as: $($cred.UserName)" -ForegroundColor DarkGray

# ── 8. Start the service ──────────────────────────────────────────────────────
Write-Host "7. Starting '$ServiceName' service..." -ForegroundColor Cyan
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
