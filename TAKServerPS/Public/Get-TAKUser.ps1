<#
.SYNOPSIS
    Gets users from a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server user information from two sources depending on the parameter set:

      - AccountList  : File-managed user accounts via /user-management/api/list-users
      - Connection   : Currently connected users via /Marti/api/users/all or /Marti/api/users/{connectionId}

    Use -AccountList for the full list of provisioned user accounts.
    Use -ConnectionId or no parameters for currently active connections.

.PARAMETER AccountList
    Returns the list of file-managed user accounts.

.PARAMETER ConnectionId
    Returns the user record for a specific active connection UID.

.PARAMETER GroupName
    Filters account-list results to users that belong to a specific group.

.EXAMPLE
    PS> Get-TAKUser -AccountList

    Returns all provisioned user accounts.

.EXAMPLE
    PS> Get-TAKUser

    Returns all currently connected users.

.EXAMPLE
    PS> Get-TAKUser -ConnectionId 'ANDROID-abc123'

    Returns the user record for the specified connection UID.

.EXAMPLE
    PS> Get-TAKUser -AccountList -GroupName 'Operators'

    Returns user accounts that belong to the Operators group.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKUser {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccountList',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [CmdletBinding(DefaultParameterSetName = 'AllConnected')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'AccountList')]
        [switch] $AccountList,

        [Parameter(Mandatory, ParameterSetName = 'ByGroup')]
        [ValidateNotNullOrEmpty()]
        [string] $GroupName,

        [Parameter(Mandatory, ParameterSetName = 'ByConnectionId')]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectionId
    )

    switch ($PSCmdlet.ParameterSetName) {
        'AccountList' {
            Invoke-TAKRequest -Path '/user-management/api/list-users'
        }
        'ByGroup' {
            $encodedGroup = [System.Uri]::EscapeDataString($GroupName)
            Invoke-TAKRequest -Path "/user-management/api/users-in-group/$encodedGroup"
        }
        'ByConnectionId' {
            $encodedId = [System.Uri]::EscapeDataString($ConnectionId)
            Invoke-TAKRequest -Path "/Marti/api/users/$encodedId"
        }
        default {
            Invoke-TAKRequest -Path '/Marti/api/users/all'
        }
    }
}
