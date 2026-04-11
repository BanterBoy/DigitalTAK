<#
.SYNOPSIS
    Enables Paperclip to start automatically when the system boots.

.DESCRIPTION
    Runs 'pm2 save' to persist the current process list, then runs
    'pm2 startup' to register pm2 with the system init daemon (systemd on
    Linux, launchd on macOS, Task Scheduler on Windows).

    On Linux, 'pm2 startup' prints a command that must be run as root to
    install the init script. This cmdlet captures and displays that command
    if it is present so the operator can run it manually.

    This cmdlet is idempotent — running it again after startup is already
    enabled simply re-saves the process list.

.EXAMPLE
    PS> Enable-PaperclipStartup

.EXAMPLE
    PS> Enable-PaperclipStartup -WhatIf
#>
function Enable-PaperclipStartup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess('pm2 process list', 'pm2 save')) {
        Write-Host '  Saving pm2 process list...' -ForegroundColor DarkGray
        $save = Invoke-Pm2Command -Arguments @('save', '--force')
        if ($save.ExitCode -ne 0) {
            throw "pm2 save failed (exit $($save.ExitCode)):`n$($save.Output -join "`n")"
        }
        Write-Host '  [OK] Process list saved.' -ForegroundColor Green
    }

    if ($PSCmdlet.ShouldProcess('system init daemon', 'pm2 startup')) {
        Write-Host '  Registering pm2 startup hook...' -ForegroundColor DarkGray
        $startup = Invoke-Pm2Command -Arguments @('startup')

        # pm2 startup may print a sudo command that must be run manually.
        $sudoLine = $startup.Output | Where-Object { $_ -match '^sudo\s+' } | Select-Object -First 1
        if ($sudoLine) {
            Write-Host ''
            Write-Host '  ACTION REQUIRED — run the following command as root:' -ForegroundColor Yellow
            Write-Host "  $sudoLine" -ForegroundColor Cyan
            Write-Host ''
        }
        elseif ($startup.ExitCode -eq 0) {
            Write-Host '  [OK] pm2 startup hook registered.' -ForegroundColor Green
        }
        else {
            Write-Warning "  pm2 startup returned exit code $($startup.ExitCode). Output:`n$($startup.Output -join "`n")"
        }
    }
}
