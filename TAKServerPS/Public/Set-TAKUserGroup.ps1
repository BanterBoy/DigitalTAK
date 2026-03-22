<#
.SYNOPSIS
    Updates group membership for a file-managed TAK Server user.

.DESCRIPTION
    Updates the group assignments for an existing user via the
    /user-management/api/update-groups PUT endpoint.

.PARAMETER UserName
    The username of the account to update.

.PARAMETER GroupList
    Bi-directional group memberships to set.

.PARAMETER InboundGroups
    Inbound (receive) group memberships to set.

.PARAMETER OutboundGroups
    Outbound (send) group memberships to set.

.EXAMPLE
    PS> Set-TAKUserGroup -UserName 'fielduser1' -GroupList 'Operators', 'Command'

    Sets fielduser1's group membership to Operators and Command.

.EXAMPLE
    PS> Set-TAKUserGroup -UserName 'sensor1' -InboundGroups 'Intel' -OutboundGroups 'FieldTeam'

    Sets sensor1 to receive from Intel and send to FieldTeam.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Set-TAKUserGroup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $UserName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $GroupList,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $InboundGroups,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $OutboundGroups
    )

    process {
        if ($PSCmdlet.ShouldProcess($UserName, 'Update TAK user groups')) {
            $body = @{ username = $UserName }
            if ($GroupList)      { $body['groupList']    = @($GroupList) }
            if ($InboundGroups)  { $body['groupListIN']  = @($InboundGroups) }
            if ($OutboundGroups) { $body['groupListOUT'] = @($OutboundGroups) }

            $null = Invoke-TAKRequest -Path '/user-management/api/update-groups' -Method Put -Body $body
            Write-Verbose "Updated group membership for TAK user: $UserName"
        }
    }
}
