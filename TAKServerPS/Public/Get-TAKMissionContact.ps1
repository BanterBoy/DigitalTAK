<#
.SYNOPSIS
    Gets contacts associated with a TAK Server mission.

.DESCRIPTION
    Retrieves the list of TAK contacts that are subscribed to or have recently
    interacted with the specified mission.

.PARAMETER Name
    The name of the mission to retrieve contacts for.

.EXAMPLE
    PS> Get-TAKMissionContact -Name 'OpBlue'

    Returns all contacts associated with the OpBlue mission.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKMissionContact {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        $encodedName = [System.Uri]::EscapeDataString($Name)
        Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName/contacts"
    }
}
