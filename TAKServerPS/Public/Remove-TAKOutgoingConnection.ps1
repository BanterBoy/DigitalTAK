<#
.SYNOPSIS
    Removes an outgoing connection from a connected TAK Server.

.DESCRIPTION
    Deletes a TAK Server outgoing connection by display name via
    DELETE /Marti/api/outgoingconnections/{name}.

.PARAMETER Name
    The display name of the outgoing connection to remove.

.EXAMPLE
    PS> Remove-TAKOutgoingConnection -Name 'HQ Server'

.EXAMPLE
    PS> Get-TAKOutgoingConnection | Where-Object enabled -eq $false |
            Select-Object -ExpandProperty displayName |
            Remove-TAKOutgoingConnection -Confirm:$false

    Removes all disabled outgoing connections.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKOutgoingConnection {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('displayName')]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Remove TAK outgoing connection')) {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            Invoke-TAKRequest -Path "/Marti/api/outgoingconnections/$encodedName" -Method Delete | Out-Null
        }
    }
}
