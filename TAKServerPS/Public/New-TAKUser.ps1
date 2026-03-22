<#
.SYNOPSIS
    Creates a new file-managed user on a connected TAK Server.

.DESCRIPTION
    Creates a new user account via the file-based user management endpoint
    /user-management/api/new-user. Accepts a PSCredential for the username and
    password to avoid passing plain-text passwords through the pipeline.

    Optionally assigns the user to one or more groups.

.PARAMETER Credential
    PSCredential containing the new username and password.

.PARAMETER GroupList
    Groups to assign to the user (bi-directional membership).

.PARAMETER InboundGroups
    Groups the user can receive data from (IN direction).

.PARAMETER OutboundGroups
    Groups the user can send data to (OUT direction).

.EXAMPLE
    PS> $cred = Get-Credential -UserName 'fielduser1' -Message 'Set password for new user'
    PS> New-TAKUser -Credential $cred -GroupList 'Operators'

    Creates user 'fielduser1' and adds them to the Operators group.

.EXAMPLE
    PS> New-TAKUser -Credential (Get-Credential) -InboundGroups 'Intel' -OutboundGroups 'Command'

    Creates a user with separate inbound and outbound group assignments.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
    Passwords are extracted from the PSCredential only at the point of the API call
    and are not stored in any variable in plain text.
#>
function New-TAKUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

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

    $userName = $Credential.UserName

    if ($PSCmdlet.ShouldProcess($userName, 'Create TAK user')) {
        # Convert SecureString password to plain text for the REST body only
        $bstr          = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $Credential.Password
        )
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $body = @{
            username = $userName
            password = $plainPassword
        }

        if ($GroupList)      { $body['groupList']    = @($GroupList) }
        if ($InboundGroups)  { $body['groupListIN']  = @($InboundGroups) }
        if ($OutboundGroups) { $body['groupListOUT'] = @($OutboundGroups) }

        $null = Invoke-TAKRequest -Path '/user-management/api/new-user' -Method Post -Body $body
        Write-Verbose "Created TAK user: $userName"
    }
}
