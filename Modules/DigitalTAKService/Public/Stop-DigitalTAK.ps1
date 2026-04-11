<#
.SYNOPSIS
    Stops the DigitalTAK service via pm2.

.DESCRIPTION
    Runs 'pm2 stop paperclip' to gracefully stop the DigitalTAK process.
    The process remains registered in pm2 and can be restarted with
    Start-DigitalTAK or Restart-DigitalTAK.

.EXAMPLE
    PS> Stop-DigitalTAK

    Stops the paperclip pm2 process.

.EXAMPLE
    PS> Stop-DigitalTAK -WhatIf

    Shows what pm2 command would be run without executing it.
#>
function Stop-DigitalTAK {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 stop')) {
        Write-Host "  Stopping $script:Pm2ProcessName..." -ForegroundColor DarkGray
        $result = Invoke-Pm2Command -Arguments @('stop', $script:Pm2ProcessName)

        if ($result.ExitCode -ne 0) {
            throw "pm2 stop failed (exit $($result.ExitCode)):`n$($result.Output -join "`n")"
        }

        Write-Host "  [OK] $script:Pm2ProcessName stopped." -ForegroundColor Green
    }
}
