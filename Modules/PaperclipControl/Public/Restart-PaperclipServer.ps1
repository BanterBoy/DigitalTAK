<#
.SYNOPSIS
    Restarts the Paperclip PM2 service.

.DESCRIPTION
    Runs 'pm2 restart paperclip'. Waits briefly then confirms port 3100 is
    accepting connections. Throws if pm2 reports a non-zero exit code.

.EXAMPLE
    PS> Restart-PaperclipServer

.EXAMPLE
    PS> Restart-PaperclipServer -WhatIf
#>
function Restart-PaperclipServer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 restart')) {
        Write-Host "  Restarting Paperclip ($script:Pm2ProcessName)..." -ForegroundColor DarkGray
        $result = Invoke-Pm2Command -Arguments @('restart', $script:Pm2ProcessName)
        if ($result.ExitCode -ne 0) {
            throw "pm2 restart failed (exit $($result.ExitCode)):`n$($result.Output -join "`n")"
        }
        Write-Host '  [OK] pm2 restart issued.' -ForegroundColor Green

        Start-Sleep -Seconds 2

        if (Test-PaperclipPort) {
            Write-Host "  [OK] Paperclip is listening on port $script:ServicePort." -ForegroundColor Green
        }
        else {
            Write-Warning "  Paperclip restarted but port $script:ServicePort is not yet responding. Check 'pm2 logs $script:Pm2ProcessName'."
        }
    }
}
