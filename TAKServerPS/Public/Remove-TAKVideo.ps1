<#
.SYNOPSIS
    Removes a video connection from a connected TAK Server.

.DESCRIPTION
    Deletes a TAK Server video connection by UID via
    DELETE /Marti/api/video/{uid}.

.PARAMETER Uid
    The UUID of the video connection to delete.

.EXAMPLE
    PS> Remove-TAKVideo -Uid '7b3c9a2e-1234-5678-abcd-ef0123456789'

.EXAMPLE
    PS> Get-TAKVideo | Where-Object active -eq $false |
            Select-Object -ExpandProperty uuid |
            Remove-TAKVideo -Confirm:$false

    Removes all inactive video connections.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKVideo {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('uuid')]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    process {
        if ($PSCmdlet.ShouldProcess($Uid, 'Remove TAK video connection')) {
            $encodedUid = [System.Uri]::EscapeDataString($Uid)
            Invoke-TAKRequest -Path "/Marti/api/video/$encodedUid" -Method Delete | Out-Null
        }
    }
}
