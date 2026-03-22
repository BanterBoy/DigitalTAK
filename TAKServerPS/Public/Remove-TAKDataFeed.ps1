<#
.SYNOPSIS
    Removes a data feed from a connected TAK Server.

.DESCRIPTION
    Deletes a TAK Server data feed via DELETE /Marti/api/datafeeds/{name}.

.PARAMETER Name
    The name of the data feed to delete.

.EXAMPLE
    PS> Remove-TAKDataFeed -Name 'SensorFeed'

.EXAMPLE
    PS> Get-TAKDataFeed | Where-Object protocol -eq 'udp' | Remove-TAKDataFeed -Confirm:$false

    Removes all UDP data feeds without prompting.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKDataFeed {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Remove TAK data feed')) {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            Invoke-TAKRequest -Path "/Marti/api/datafeeds/$encodedName" -Method Delete | Out-Null
        }
    }
}
