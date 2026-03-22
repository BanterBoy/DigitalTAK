<#
.SYNOPSIS
    Blocks until a systemd service reaches the 'active' state on a remote host.

.DESCRIPTION
    Internal helper used by TAKInstall cmdlets after service restart operations.
    Polls 'systemctl is-active <service>' every PollIntervalSeconds until the
    service is active or the timeout is exceeded.

.PARAMETER Session
    An active Posh-SSH SSH session (from New-SSHSession).

.PARAMETER ServiceName
    The systemd service unit name to wait for (default: takserver).

.PARAMETER TimeoutSeconds
    Maximum seconds to wait before throwing a timeout error (default: 300).

.PARAMETER PollIntervalSeconds
    Seconds between each poll attempt (default: 10).
#>
function Wait-TAKServiceReady {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $Session,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ServiceName = 'takserver',

        [Parameter()]
        [ValidateRange(30, 600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [ValidateRange(5, 60)]
        [int] $PollIntervalSeconds = 10
    )

    Write-Verbose "Waiting for '$ServiceName' to become active (timeout ${TimeoutSeconds}s)..."

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $result = Invoke-SSHCommand -SSHSession $Session -Command "systemctl is-active $ServiceName" -ErrorAction SilentlyContinue

        if ($result -and $result.Output.Trim() -eq 'active') {
            Write-Verbose "'$ServiceName' is active."
            Write-Progress -Activity "Waiting for $ServiceName" -Completed
            return
        }

        $elapsed  = [int]$stopwatch.Elapsed.TotalSeconds
        $remaining = $TimeoutSeconds - $elapsed
        $pct       = [int](($elapsed / $TimeoutSeconds) * 100)

        Write-Progress -Activity "Waiting for $ServiceName" `
            -Status "Not yet active — ${remaining}s remaining" `
            -PercentComplete $pct

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    $stopwatch.Stop()
    Write-Progress -Activity "Waiting for $ServiceName" -Completed

    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.TimeoutException]::new("Service '$ServiceName' did not become active within ${TimeoutSeconds}s."),
        'TAKServiceTimeout',
        [System.Management.Automation.ErrorCategory]::OperationTimeout,
        $ServiceName
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
