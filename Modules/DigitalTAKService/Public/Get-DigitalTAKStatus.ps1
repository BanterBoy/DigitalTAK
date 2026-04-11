<#
.SYNOPSIS
    Returns the current status of the DigitalTAK service.

.DESCRIPTION
    Checks both the TCP port (3100) and the pm2 process descriptor for the
    DigitalTAK service and returns a structured status object.

.OUTPUTS
    PSCustomObject with properties:
      ServiceName   — pm2 process name ('paperclip')
      Port          — service port (3100)
      PortListening — whether port 3100 is accepting connections
      Pm2Status     — pm2 process status string ('online', 'stopped', 'errored', 'not found')
      Pid           — process ID reported by pm2 (0 if not running)
      UptimeMs      — milliseconds the process has been online (0 if not running)

.EXAMPLE
    PS> Get-DigitalTAKStatus

    ServiceName   : paperclip
    Port          : 3100
    PortListening : True
    Pm2Status     : online
    Pid           : 98765
    UptimeMs      : 3600000

.EXAMPLE
    PS> $status = Get-DigitalTAKStatus
    PS> if ($status.Pm2Status -ne 'online') { Start-DigitalTAK }
#>
function Get-DigitalTAKStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $portListening = Test-DigitalTAKPort
    $proc          = Get-Pm2ProcessInfo

    $pm2Status = if ($null -eq $proc) {
        'not found'
    }
    else {
        $proc.pm2_env.status
    }

    $pid_val  = if ($proc -and $proc.pid)              { [int]$proc.pid }              else { 0 }
    $uptime   = if ($proc -and $proc.pm2_env.pm_uptime) { [long]$proc.pm2_env.pm_uptime } else { 0L }

    [PSCustomObject]@{
        PSTypeName    = 'DigitalTAKService.Status'
        ServiceName   = $script:Pm2ProcessName
        Port          = $script:ServicePort
        PortListening = $portListening
        Pm2Status     = $pm2Status
        Pid           = $pid_val
        UptimeMs      = $uptime
    }
}
