<#
.SYNOPSIS
    Deletes a file-managed user from a connected TAK Server.

.DESCRIPTION
    Removes a user account via the /user-management/api/delete-user/{username}
    DELETE endpoint. This removes the account but does not revoke the user's
    certificates. Use Remove-TAKCertificate separately for that.

.PARAMETER UserName
    The username of the account to delete. Accepts pipeline input by property name.

.EXAMPLE
    PS> Remove-TAKUser -UserName 'exuser1'

    Deletes the user account 'exuser1' after confirmation.

.EXAMPLE
    PS> Get-TAKUser -AccountList | Where-Object { $_.username -like 'temp_*' } | Remove-TAKUser

    Deletes all user accounts with names starting with 'temp_'.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(
            Mandatory,
            Position                        = 0,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string] $UserName
    )

    process {
        if ($PSCmdlet.ShouldProcess($UserName, 'Delete TAK user')) {
            $encodedName = [System.Uri]::EscapeDataString($UserName)
            $null = Invoke-TAKRequest -Path "/user-management/api/delete-user/$encodedName" -Method Delete
            Write-Verbose "Deleted TAK user: $UserName"
        }
    }
}
