<#
.SYNOPSIS
    Starts the Paperclip PM2 service.

.DESCRIPTION
    Checks whether the Paperclip service is already listening on port 3100.
    If it is, prints the current status and returns without changes.

    If the service is not running, attempts to restore it from the pm2 process
    dump via 'pm2 resurrect'. If resurrection fails or no dump exists, falls
    back to 'pm2 start <ConfigPath>' using the ecosystem config file.

    After starting, waits briefly and confirms port 3100 is accepting connections.

.PARAMETER ConfigPath
    Path to the pm2 ecosystem config file used as a fallback when resurrection
    has no dump to restore. Defaults to 'ecosystem.config.js' in the current
    working directory.

.EXAMPLE
    PS> Start-PaperclipServer

.EXAMPLE
    PS> Start-PaperclipServer -ConfigPath '/opt/paperclip/ecosystem.config.js'

.EXAMPLE
    PS> Start-PaperclipServer -WhatIf
#>
function Start-PaperclipServer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string] $ConfigPath = (Join-Path (Get-Location) 'ecosystem.config.js')
    )

    $ErrorActionPreference = 'Stop'

    if (Test-PaperclipPort) {
        Write-Host "  [OK] Paperclip is already running on port $script:ServicePort." -ForegroundColor Green
        Get-PaperclipStatus
        return
    }

    if ($PSCmdlet.ShouldProcess($script:Pm2ProcessName, 'pm2 resurrect')) {
        Write-Host '  Attempting pm2 resurrect...' -ForegroundColor DarkGray
        $resurrect = Invoke-Pm2Command -Arguments @('resurrect')

        if ($resurrect.ExitCode -eq 0 -and ($resurrect.Output -notmatch 'No process dump|nothing to resurrect|error')) {
            Write-Host '  [OK] pm2 resurrect succeeded.' -ForegroundColor Green
        }
        else {
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

        Start-Sleep -Seconds 2

        if (Test-PaperclipPort) {
            Write-Host "  [OK] Paperclip is listening on port $script:ServicePort." -ForegroundColor Green
        }
        else {
            Write-Warning "  Paperclip process started but port $script:ServicePort is not yet responding. Check 'pm2 logs $script:Pm2ProcessName'."
        }
    }
}
