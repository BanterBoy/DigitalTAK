<#
.SYNOPSIS
    Starts the DigitalTAK service via pm2.

.DESCRIPTION
    Checks whether the DigitalTAK service is already listening on port 3100.
    If it is, prints the current status and returns without making changes.

    If the service is not running, attempts to restore it from the pm2 process
    dump via 'pm2 resurrect'. If resurrection fails or no dump exists, falls
    back to 'pm2 start <ConfigPath>' using the ecosystem config file.

    After starting, waits briefly and confirms port 3100 is accepting connections.

.PARAMETER ConfigPath
    Path to the pm2 ecosystem config file used as a fallback when resurrection
    has no dump to restore. Defaults to 'ecosystem.config.js' in the current
    working directory.

.EXAMPLE
    PS> Start-DigitalTAK

    Starts the service using the ecosystem.config.js in the current directory.

.EXAMPLE
    PS> Start-DigitalTAK -ConfigPath '/opt/digitak/ecosystem.config.js'

    Starts the service using an explicit config path.

.EXAMPLE
    PS> Start-DigitalTAK -WhatIf

    Shows what pm2 command would be run without executing it.
#>
function Start-DigitalTAK {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string] $ConfigPath = (Join-Path (Get-Location) 'ecosystem.config.js')
    )

    $ErrorActionPreference = 'Stop'

    # If already running, report and exit.
    if (Test-DigitalTAKPort) {
        Write-Host "  [OK] DigitalTAK is already running on port $script:ServicePort." -ForegroundColor Green
        Get-DigitalTAKStatus
        return
    }

    # Try pm2 resurrect first (restores the persisted process list).
    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 resurrect')) {
        Write-Host '  Attempting pm2 resurrect...' -ForegroundColor DarkGray
        $resurrect = Invoke-Pm2Command -Arguments @('resurrect')

        if ($resurrect.ExitCode -eq 0 -and ($resurrect.Output -notmatch 'No process dump|nothing to resurrect|error' )) {
            Write-Host '  [OK] pm2 resurrect succeeded.' -ForegroundColor Green
        }
        else {
            # Fall back to pm2 start with the ecosystem config.
            if (-not (Test-Path $ConfigPath)) {
                throw "pm2 resurrect failed and ecosystem config not found at '$ConfigPath'. Provide -ConfigPath."
            }

            Write-Host "  pm2 resurrect found no dump — starting from $ConfigPath..." -ForegroundColor DarkGray
            if ($PSCmdlet.ShouldProcess($ConfigPath, 'pm2 start')) {
                $start = Invoke-Pm2Command -Arguments @('start', $ConfigPath)
                if ($start.ExitCode -ne 0) {
                    throw "pm2 start failed (exit $($start.ExitCode)):`n$($start.Output -join "`n")"
                }
                Write-Host '  [OK] pm2 start succeeded.' -ForegroundColor Green
            }
        }

        # Give the process a moment to bind the port.
        Start-Sleep -Seconds 2

        if (Test-DigitalTAKPort) {
            Write-Host "  [OK] DigitalTAK is listening on port $script:ServicePort." -ForegroundColor Green
        }
        else {
            Write-Warning "  DigitalTAK process started but port $script:ServicePort is not yet responding. Check 'pm2 logs $script:Pm2ProcessName'."
        }
    }
}
