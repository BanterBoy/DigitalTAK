<#
.SYNOPSIS
    Stops the Paperclip PM2 service.

.DESCRIPTION
    Runs 'pm2 stop paperclip'. If pm2 reports a non-zero exit code the
    cmdlet throws so the caller can handle the error.

.EXAMPLE
    PS> Stop-PaperclipServer

.EXAMPLE
    PS> Stop-PaperclipServer -WhatIf
#>
function Stop-PaperclipServer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 stop')) {
        Write-Host "  Stopping Paperclip ($script:Pm2ProcessName)..." -ForegroundColor DarkGray
        $result = Invoke-Pm2Command -Arguments @('stop', $script:Pm2ProcessName)
        if ($result.ExitCode -ne 0) {
            throw "pm2 stop failed (exit $($result.ExitCode)):`n$($result.Output -join "`n")"
        }
        Write-Host '  [OK] Paperclip stopped.' -ForegroundColor Green
    }
}
