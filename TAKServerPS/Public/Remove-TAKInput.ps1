<#
.SYNOPSIS
    Removes a network input from a connected TAK Server.

.DESCRIPTION
    Deletes a TAK Server input via DELETE /Marti/api/inputs/{name}.

.PARAMETER Name
    The name of the input to delete.

.EXAMPLE
    PS> Remove-TAKInput -Name 'SACast'

.EXAMPLE
    PS> Get-TAKInput | Where-Object port -gt 9000 | Remove-TAKInput -Confirm:$false

    Removes all inputs using ports above 9000 without prompting.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKInput {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Remove TAK input')) {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            Invoke-TAKRequest -Path "/Marti/api/inputs/$encodedName" -Method Delete | Out-Null
        }
    }
}
