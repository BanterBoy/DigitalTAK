<#
.SYNOPSIS
    Gets contacts from a connected TAK Server.

.DESCRIPTION
    Retrieves the list of TAK clients (Remote Contacts) visible to the server.
    Contacts represent TAK devices/users that have connected and are tracked.

.PARAMETER SortBy
    Sort field. Valid values: CALLSIGN (default), UID.

.PARAMETER Direction
    Sort direction. Valid values: ASCENDING (default), DESCENDING.

.PARAMETER NoFederates
    When specified, excludes federated contacts from the results.

.PARAMETER Full
    Returns the full contact record including group mapping details.
    When omitted, returns the lightweight summary.

.EXAMPLE
    PS> Get-TAKContact

    Returns all contacts sorted by callsign ascending.

.EXAMPLE
    PS> Get-TAKContact -SortBy UID -Direction DESCENDING -NoFederates

    Returns non-federated contacts sorted by UID descending.

.EXAMPLE
    PS> Get-TAKContact -Full

    Returns full contact records.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKContact {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [ValidateSet('CALLSIGN', 'UID')]
        [string] $SortBy = 'CALLSIGN',

        [Parameter()]
        [ValidateSet('ASCENDING', 'DESCENDING')]
        [string] $Direction = 'ASCENDING',

        [Parameter()]
        [switch] $NoFederates,

        [Parameter()]
        [switch] $Full
    )

    $query = @{
        sortBy      = $SortBy
        direction   = $Direction
        noFederates = $NoFederates.IsPresent.ToString().ToLower()
    }

    if ($Full) {
        Invoke-TAKRequest -Path '/Marti/api/contacts/all/full' -QueryParameters $query
    }
    else {
        Invoke-TAKRequest -Path '/Marti/api/contacts/all' -QueryParameters $query
    }
}
