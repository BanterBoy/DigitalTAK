<#!
.SYNOPSIS
    Blocks until the TAK admin web surface is reachable on the remote host.

.DESCRIPTION
    Internal helper used before admin certificate promotion. The TAK service can
    report as systemd-active before the WebTAK/admin surface is fully ready, so
    this helper waits for the HTTPS listener and a valid HTTP response on the
    local admin endpoints.

.PARAMETER Session
    An active Posh-SSH SSH session (from New-SSHSession).

.PARAMETER TimeoutSeconds
    Maximum seconds to wait before throwing a timeout error (default: 300).

.PARAMETER PollIntervalSeconds
    Seconds between each poll attempt (default: 10).
#>
function Wait-TAKAdminApiReady {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $Session,

        [Parameter()]
        [ValidateRange(30, 600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [ValidateRange(5, 60)]
        [int] $PollIntervalSeconds = 10
    )

    $readinessCommand = 'if ! systemctl is-active --quiet takserver; then echo service-inactive; exit 1; fi; if ! sudo ss -tln | grep -E 8443\|8446 >/dev/null; then echo ports-not-listening; exit 1; fi; if curl -skI https://localhost:8443/ >/dev/null 2>&1; then echo ready-8443; exit 0; fi; if curl -skI https://localhost:8446/ >/dev/null 2>&1; then echo ready-8446; exit 0; fi; echo https-not-ready; exit 1'

    Write-Verbose "Waiting for TAK admin API to become reachable (timeout ${TimeoutSeconds}s)..."

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $result = Invoke-TAKRemoteCommand -Session $Session -Description 'Check TAK admin API readiness' -Command $readinessCommand -AllowFailure

        if ($result.ExitStatus -eq 0) {
            Write-Verbose 'TAK admin API is reachable.'
            Write-Progress -Activity 'Waiting for TAK admin API' -Completed
            return
        }

        $elapsed = [int]$stopwatch.Elapsed.TotalSeconds
        $remaining = $TimeoutSeconds - $elapsed
        $pct = [int](($elapsed / $TimeoutSeconds) * 100)
        $detail = ($result.Output | Out-String).Trim()
        if (-not $detail) {
            $detail = ($result.Error | Out-String).Trim()
        }
        if (-not $detail) {
            $detail = 'Not yet reachable'
        }

        Write-Progress -Activity 'Waiting for TAK admin API' `
            -Status "$detail — ${remaining}s remaining" `
            -PercentComplete $pct

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    $stopwatch.Stop()
    Write-Progress -Activity 'Waiting for TAK admin API' -Completed

    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.TimeoutException]::new("TAK admin API did not become reachable within ${TimeoutSeconds}s."),
        'TAKAdminApiTimeout',
        [System.Management.Automation.ErrorCategory]::OperationTimeout,
        $Session.Host
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}