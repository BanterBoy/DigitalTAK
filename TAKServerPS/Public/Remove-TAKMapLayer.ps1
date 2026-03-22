<#
.SYNOPSIS
    Removes a map layer from a connected TAK Server.

.DESCRIPTION
    Deletes a TAK Server map layer by UID via DELETE /Marti/api/maplayers/{uid}.

.PARAMETER Uid
    The UID of the map layer to delete.

.EXAMPLE
    PS> Remove-TAKMapLayer -Uid '7b3c9a2e-1234-5678-abcd-ef0123456789'

.EXAMPLE
    PS> Get-TAKMapLayer | Where-Object name -like 'TEMP_*' |
            Remove-TAKMapLayer -Confirm:$false

    Removes all map layers whose name starts with 'TEMP_'.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKMapLayer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    process {
        if ($PSCmdlet.ShouldProcess($Uid, 'Remove TAK map layer')) {
            $encodedUid = [System.Uri]::EscapeDataString($Uid)
            Invoke-TAKRequest -Path "/Marti/api/maplayers/$encodedUid" -Method Delete | Out-Null
        }
    }
}
