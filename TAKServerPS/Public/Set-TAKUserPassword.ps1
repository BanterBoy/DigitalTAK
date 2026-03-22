<#
.SYNOPSIS
    Changes the password for a file-managed TAK Server user.

.DESCRIPTION
    Updates a user's password via the /user-management/api/change-user-password PUT
    endpoint. Accepts a PSCredential so the new password is never passed as a plain-
    text string parameter.

.PARAMETER Credential
    PSCredential containing the username and the new password to set.

.EXAMPLE
    PS> Set-TAKUserPassword -Credential (Get-Credential -UserName 'fielduser1' -Message 'New password')

    Changes the password for 'fielduser1'.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Set-TAKUserPassword {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    $userName = $Credential.UserName

    if ($PSCmdlet.ShouldProcess($userName, 'Change TAK user password')) {
        $bstr          = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $body = @{
            username = $userName
            password = $plainPassword
        }

        $null = Invoke-TAKRequest -Path '/user-management/api/change-user-password' -Method Put -Body $body
        Write-Verbose "Changed password for TAK user: $userName"
    }
}
