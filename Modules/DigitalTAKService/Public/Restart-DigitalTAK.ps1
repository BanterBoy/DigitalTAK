<#
.SYNOPSIS
    Restarts the DigitalTAK service via pm2.

.DESCRIPTION
    Runs 'pm2 restart paperclip' to perform a graceful in-place restart of the
    DigitalTAK process. The process is replaced with zero registered-downtime —
    pm2 starts the new instance before stopping the old one.

    Use after configuration changes or to recover from a non-fatal error state.

.EXAMPLE
    PS> Restart-DigitalTAK

    Restarts the paperclip pm2 process.

.EXAMPLE
    PS> Restart-DigitalTAK -WhatIf

    Shows what pm2 command would be run without executing it.
#>
function Restart-DigitalTAK {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 restart')) {
        Write-Host "  Restarting $script:Pm2ProcessName..." -ForegroundColor DarkGray
        $result = Invoke-Pm2Command -Arguments @('restart', $script:Pm2ProcessName)

        if ($result.ExitCode -ne 0) {
            throw "pm2 restart failed (exit $($result.ExitCode)):`n$($result.Output -join "`n")"
        }

        Write-Host "  [OK] $script:Pm2ProcessName restarted." -ForegroundColor Green

        # Brief settle time then confirm port.
        Start-Sleep -Seconds 2

        if (Test-DigitalTAKPort) {
            Write-Host "  [OK] DigitalTAK is listening on port $script:ServicePort." -ForegroundColor Green
        }
        else {
            Write-Warning "  Restart succeeded but port $script:ServicePort is not yet responding. Check 'pm2 logs $script:Pm2ProcessName'."
        }
    }
}
