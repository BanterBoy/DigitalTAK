<#
.SYNOPSIS
    Disables Paperclip from starting automatically when the system boots.

.DESCRIPTION
    Runs 'pm2 unstartup' to deregister pm2 from the system init daemon,
    then runs 'pm2 save --force' to clear the saved process dump so that
    pm2 does not auto-resurrect the process on the next manual startup.

    On Linux, 'pm2 unstartup' may print a sudo command that must be run
    as root to remove the init script. This cmdlet displays that command
    when present.

    This cmdlet is idempotent — if pm2 startup was never enabled it exits
    cleanly without error.

.EXAMPLE
    PS> Disable-PaperclipStartup

.EXAMPLE
    PS> Disable-PaperclipStartup -WhatIf
#>
function Disable-PaperclipStartup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess('system init daemon', 'pm2 unstartup')) {
        Write-Host '  Deregistering pm2 startup hook...' -ForegroundColor DarkGray
        $unstartup = Invoke-Pm2Command -Arguments @('unstartup')

        $sudoLine = $unstartup.Output | Where-Object { $_ -match '^sudo\s+' } | Select-Object -First 1
        if ($sudoLine) {
            Write-Host ''
            Write-Host '  ACTION REQUIRED — run the following command as root:' -ForegroundColor Yellow
            Write-Host "  $sudoLine" -ForegroundColor Cyan
            Write-Host ''
        }
        elseif ($unstartup.ExitCode -eq 0) {
            Write-Host '  [OK] pm2 startup hook removed.' -ForegroundColor Green
        }
        else {
            Write-Warning "  pm2 unstartup returned exit code $($unstartup.ExitCode). It may not have been registered."
        }
    }

    # Clear the saved dump so pm2 does not auto-resurrect on next manual start.
    if ($PSCmdlet.ShouldProcess('pm2 process dump', 'pm2 save --force (clear)')) {
        Write-Host '  Clearing saved pm2 process list...' -ForegroundColor DarkGray
        $save = Invoke-Pm2Command -Arguments @('save', '--force')
        if ($save.ExitCode -ne 0) {
            Write-Warning "  pm2 save --force failed (exit $($save.ExitCode)). Dump may still exist."
        }
        else {
            Write-Host '  [OK] Saved process list cleared.' -ForegroundColor Green
        }
    }
}
