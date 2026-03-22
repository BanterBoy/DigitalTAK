<#
.SYNOPSIS
    Ends the current TAK Server session.

.DESCRIPTION
    Calls the /logout endpoint on the connected TAK Server, then clears the
    module-level session so subsequent cmdlets will require a new Connect-TAKServer call.

.EXAMPLE
    PS> Disconnect-TAKServer

    Logs out and clears the active session.

.EXAMPLE
    PS> Disconnect-TAKServer -Force

    Clears the local session without attempting the remote logout call.

.OUTPUTS
    void

.NOTES
    If the server is unreachable, the local session is still cleared.
#>
function Disconnect-TAKServer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([void])]
    param (
        [Parameter()]
        [switch] $Force
    )

    if (-not $script:TAKSession) {
        Write-Verbose 'No active TAK Server session to disconnect.'
        return
    }

    $target = $script:TAKSession.BaseUrl

    if ($PSCmdlet.ShouldProcess($target, 'Disconnect TAK Server session')) {
        if (-not $Force) {
            try {
                $null = Invoke-TAKRequest -Path '/logout' -Method 'Post' -ErrorAction Stop
                Write-Verbose "Successfully logged out from $target"
            }
            catch {
                Write-Warning "Remote logout call failed: $($PSItem.Exception.Message). Clearing local session anyway."
            }
        }

        $script:TAKSession = $null
        Write-Verbose "Disconnected from $target"
    }
}
