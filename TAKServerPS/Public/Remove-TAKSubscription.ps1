<#
.SYNOPSIS
    Removes a client subscription from a connected TAK Server.

.DESCRIPTION
    Disconnects and removes a client subscription via
    DELETE /Marti/api/subscriptions/delete/{uid}.

.PARAMETER Uid
    The UID of the subscription to remove.

.EXAMPLE
    PS> Remove-TAKSubscription -Uid 'ANDROID-abc123'

.EXAMPLE
    PS> Get-TAKSubscription | Where-Object callsign -like 'OLD-*' | Remove-TAKSubscription -Confirm:$false

    Removes all subscriptions whose callsign starts with 'OLD-'.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKSubscription {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    process {
        if ($PSCmdlet.ShouldProcess($Uid, 'Remove TAK subscription')) {
            $encodedUid = [System.Uri]::EscapeDataString($Uid)
            Invoke-TAKRequest -Path "/Marti/api/subscriptions/delete/$encodedUid" -Method Delete | Out-Null
        }
    }
}
