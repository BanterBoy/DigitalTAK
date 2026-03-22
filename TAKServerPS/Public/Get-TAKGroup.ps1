<#
.SYNOPSIS
    Gets groups from a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server group definitions. By default returns all groups visible
    to the authenticated user. Optionally filters by group name or direction.

.PARAMETER Name
    The name of a specific group to retrieve.

.PARAMETER Direction
    Filters results to IN or OUT direction groups.

.PARAMETER All
    Returns all groups including those not visible to the current user.
    Requires administrative privileges.

.EXAMPLE
    PS> Get-TAKGroup

    Returns all groups visible to the current user.

.EXAMPLE
    PS> Get-TAKGroup -All

    Returns every group on the server (admin only).

.EXAMPLE
    PS> Get-TAKGroup -Name 'Operators' -Direction IN

    Returns the IN-direction configuration for the Operators group.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKGroup {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateSet('IN', 'OUT')]
        [string] $Direction,

        [Parameter(ParameterSetName = 'AllAdmin')]
        [switch] $All
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByName' {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            if ($Direction) {
                Invoke-TAKRequest -Path "/Marti/api/groups/$encodedName/$Direction"
            }
            else {
                Invoke-TAKRequest -Path "/Marti/api/groups/$encodedName/IN"
            }
        }
        'AllAdmin' {
            Invoke-TAKRequest -Path '/Marti/api/groups/all'
        }
        default {
            Invoke-TAKRequest -Path '/Marti/api/groups'
        }
    }
}
