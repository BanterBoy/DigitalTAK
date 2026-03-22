<#
.SYNOPSIS
    Deletes a mission from a connected TAK Server.

.DESCRIPTION
    Removes a TAK Server mission via DELETE /Marti/api/missions. Accepts mission
    names from the pipeline.

.PARAMETER Name
    The name of the mission to delete. Accepts pipeline input by property name.

.EXAMPLE
    PS> Remove-TAKMission -Name 'OpBlue'

    Deletes the mission named 'OpBlue' after confirmation.

.EXAMPLE
    PS> Get-TAKMission -Tool 'test' | Remove-TAKMission

    Deletes all missions with tool type 'test'.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKMission {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(
            Mandatory,
            Position                        = 0,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Delete TAK mission')) {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            $null = Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName" -Method Delete
            Write-Verbose "Deleted TAK mission: $Name"
        }
    }
}
