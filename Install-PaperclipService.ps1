#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Migrates Paperclip from PM2/NSSM to a Windows Scheduled Task.

.DESCRIPTION
    Run once as Administrator. Performs the following:
      1. Removes any existing PM2 process and data
      2. Removes any existing NSSM Paperclip service
      3. Installs paperclipai globally via npm
      4. Creates a Windows Scheduled Task that starts paperclipai at system
         startup, running as the current user

    Windows Scheduled Tasks handle Azure AD accounts reliably — unlike NSSM
    services which fail with error 1068 on AzureAD-joined machines.

    After running, manage with:
      Get-ScheduledTask -TaskName Paperclip
      Start-ScheduledTask -TaskName Paperclip
      Stop-ScheduledTask  -TaskName Paperclip
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$TaskName = 'Paperclip'
$WorkDir  = 'C:\Users\LukeLeigh\DigitalTAK'
$LogDir   = "$WorkDir\logs"

# ── 1. Stop and remove PM2 ──────────────────────────────────────────────────
Write-Host '1. Removing PM2 (if present)...' -ForegroundColor Cyan

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

@("$env:USERPROFILE\.pm2", "$env:APPDATA\pm2") | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Recurse -Force
        Write-Host "   Removed: $_" -ForegroundColor DarkGray
    }
}

# ── 2. Remove existing NSSM service (if present) ────────────────────────────
Write-Host '2. Removing NSSM service (if present)...' -ForegroundColor Cyan

$NssmExe = "$WorkDir\tools\nssm.exe"
$existingSvc = & sc.exe query $TaskName 2>&1
if ($existingSvc -match 'SERVICE_NAME') {
    if (Test-Path $NssmExe) {
        & $NssmExe stop   $TaskName 2>&1 | Out-Null
        & $NssmExe remove $TaskName confirm 2>&1 | Out-Null
        Write-Host '   NSSM service removed.' -ForegroundColor DarkGray
    } else {
        & sc.exe stop $TaskName   2>&1 | Out-Null
        & sc.exe delete $TaskName 2>&1 | Out-Null
        Write-Host '   Service removed via sc.exe.' -ForegroundColor DarkGray
    }
} else {
    Write-Host '   No existing service found.' -ForegroundColor DarkGray
}

# ── 3. Install paperclipai globally ──────────────────────────────────────────
Write-Host '3. Installing paperclipai globally...' -ForegroundColor Cyan

$nodeExe = Get-Command node -ErrorAction Stop
Write-Host "   Node.js: $($nodeExe.Source)" -ForegroundColor DarkGray

& npm install -g paperclipai 2>&1 | Out-Null
$paperclipCmd = Get-Command paperclipai -ErrorAction SilentlyContinue
if (-not $paperclipCmd) {
    throw 'npm install -g paperclipai succeeded but the command is not on PATH. Check: npm prefix -g'
}
Write-Host "   paperclipai: $($paperclipCmd.Source)" -ForegroundColor DarkGray

# ── 4. Create log directory ──────────────────────────────────────────────────
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# ── 5. Remove existing scheduled task (if present) ───────────────────────────
Write-Host '4. Configuring scheduled task...' -ForegroundColor Cyan

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Stop-ScheduledTask  -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host '   Removed existing scheduled task.' -ForegroundColor DarkGray
}

# ── 6. Build the scheduled task ──────────────────────────────────────────────
Write-Host '5. Creating scheduled task...' -ForegroundColor Cyan

# Resolve the global paperclipai entry point for node.exe
$npmPrefix  = (& npm prefix -g).Trim()
$entryPoint = Join-Path $npmPrefix 'node_modules\paperclipai\dist\index.js'
if (-not (Test-Path $entryPoint)) {
    throw "Cannot locate paperclipai entry point. Expected: $entryPoint"
}

$nodePath = $nodeExe.Source
Write-Host "   Entry point: $entryPoint" -ForegroundColor DarkGray

# The task runs node.exe directly with the paperclipai entry point.
# Output is redirected to log files. The >> append ensures logs accumulate.
$action = New-ScheduledTaskAction `
    -Execute 'cmd.exe' `
    -Argument "/c `"$nodePath`" `"$entryPoint`" run >> `"$LogDir\paperclip-stdout.log`" 2>> `"$LogDir\paperclip-stderr.log`"" `
    -WorkingDirectory $WorkDir

# Trigger: at system startup (runs even before user logs in if "run whether
# logged on or not" is set, but we use AtLogOn for the current user to avoid
# credential prompts — Azure AD accounts work natively with AtLogOn).
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

# Also add a startup trigger so it runs if the machine reboots unattended.
$startupTrigger = New-ScheduledTaskTrigger -AtStartup

# Principal: run as the current user, highest privileges not needed.
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType S4U `
    -RunLevel Limited

# Settings: restart on failure, don't stop after 3 days, allow parallel.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger, $startupTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Paperclip AI agent runner (DigitalTAK)' `
    -Force | Out-Null

Write-Host "   Task registered as: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor DarkGray

# ── 7. Start the task now ────────────────────────────────────────────────────
Write-Host '6. Starting task...' -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 4

$taskInfo = Get-ScheduledTask -TaskName $TaskName
$taskStatus = $taskInfo.State
if ($taskStatus -eq 'Running') {
    Write-Host "[OK] $TaskName task is running." -ForegroundColor Green
} else {
    Write-Warning "$TaskName state: $taskStatus — check logs: $LogDir"
    # Show last run result for debugging
    $lastResult = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
    Write-Host "   Last result code: $lastResult" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Migration complete.' -ForegroundColor Green
Write-Host 'Task management:' -ForegroundColor DarkGray
Write-Host "  Start-ScheduledTask -TaskName $TaskName" -ForegroundColor DarkGray
Write-Host "  Stop-ScheduledTask  -TaskName $TaskName" -ForegroundColor DarkGray
Write-Host "  Get-ScheduledTask   -TaskName $TaskName" -ForegroundColor DarkGray
Write-Host "  Get-ScheduledTaskInfo -TaskName $TaskName   (last run result)" -ForegroundColor DarkGray
Write-Host "  Logs: $LogDir" -ForegroundColor DarkGray
