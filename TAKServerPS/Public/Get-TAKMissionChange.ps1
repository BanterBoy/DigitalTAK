<#
.SYNOPSIS
    Gets change history for a TAK Server mission.

.DESCRIPTION
    Retrieves the change log for a named mission via
    /Marti/api/missions/{name}/changes. Changes represent content additions,
    removals, and modifications including CoT events, files, and map layers.

.PARAMETER Name
    The mission name to retrieve changes for.

.PARAMETER SecAgo
    Return only changes from the last N seconds.

.PARAMETER Start
    Return only changes after this datetime.

.PARAMETER End
    Return only changes before this datetime.

.EXAMPLE
    PS> Get-TAKMissionChange -Name 'OpBlue'

    Returns all changes for the OpBlue mission.

.EXAMPLE
    PS> Get-TAKMissionChange -Name 'OpBlue' -SecAgo 3600

    Returns changes in the last hour.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKMissionChange {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $SecAgo,

        [Parameter()]
        [datetime] $Start,

        [Parameter()]
        [datetime] $End
    )

    process {
        $encodedName = [System.Uri]::EscapeDataString($Name)
        $query = @{}
        if ($SecAgo -gt 0) { $query['secago'] = [string]$SecAgo }
        if ($Start)        { $query['start']  = $Start.ToString('o') }
        if ($End)          { $query['end']    = $End.ToString('o') }

        Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName/changes" -QueryParameters $query
    }
}
