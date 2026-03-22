<#
.SYNOPSIS
    Gets missions from a connected TAK Server.

.DESCRIPTION
    Retrieves mission definitions. Supports listing all missions, fetching a
    single mission by name or GUID, and filtering the list by tool type or
    password-protection status.

.PARAMETER Name
    Returns the mission with this name.

.PARAMETER Guid
    Returns the mission with this GUID.

.PARAMETER Tool
    Filters the mission list to missions with the specified tool value (e.g. 'public', 'vbm').

.PARAMETER PasswordProtected
    Filters the mission list to password-protected missions only.

.PARAMETER IncludeChanges
    When retrieving a single mission, includes the change log in the response.

.PARAMETER IncludeLogs
    When retrieving a single mission, includes log entries in the response.

.PARAMETER SecAgo
    When retrieving a single mission, returns only content changed within this
    many seconds.

.PARAMETER Start
    When retrieving a single mission, returns content changed after this datetime.

.PARAMETER End
    When retrieving a single mission, returns content changed before this datetime.

.EXAMPLE
    PS> Get-TAKMission

    Returns all missions.

.EXAMPLE
    PS> Get-TAKMission -Name 'OpBlue'

    Returns the mission named 'OpBlue'.

.EXAMPLE
    PS> Get-TAKMission -Guid 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

    Returns the mission with the specified GUID.

.EXAMPLE
    PS> Get-TAKMission -Tool 'public' -IncludeChanges

    Returns all public missions including change details.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKMission {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = 'ByGuid')]
        [ValidateNotNullOrEmpty()]
        [string] $Guid,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string] $Tool,

        [Parameter(ParameterSetName = 'List')]
        [switch] $PasswordProtected,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByGuid')]
        [switch] $IncludeChanges,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByGuid')]
        [switch] $IncludeLogs,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByGuid')]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $SecAgo,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByGuid')]
        [datetime] $Start,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByGuid')]
        [datetime] $End
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByName' {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            $query = @{}
            if ($IncludeChanges) { $query['changes'] = 'true' }
            if ($IncludeLogs)    { $query['logs']    = 'true' }
            if ($SecAgo -gt 0)   { $query['secago']  = [string]$SecAgo }
            if ($Start)          { $query['start']   = $Start.ToString('o') }
            if ($End)            { $query['end']      = $End.ToString('o') }
            Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName" -QueryParameters $query
        }
        'ByGuid' {
            $encodedGuid = [System.Uri]::EscapeDataString($Guid)
            $query = @{}
            if ($IncludeChanges) { $query['changes'] = 'true' }
            if ($IncludeLogs)    { $query['logs']    = 'true' }
            if ($SecAgo -gt 0)   { $query['secago']  = [string]$SecAgo }
            if ($Start)          { $query['start']   = $Start.ToString('o') }
            if ($End)            { $query['end']      = $End.ToString('o') }
            Invoke-TAKRequest -Path "/Marti/api/missions/guid/$encodedGuid" -QueryParameters $query
        }
        default {
            $query = @{}
            if ($PasswordProtected) { $query['passwordProtected'] = 'true' }
            if ($Tool)              { $query['tool'] = $Tool }
            Invoke-TAKRequest -Path '/Marti/api/missions' -QueryParameters $query
        }
    }
}
