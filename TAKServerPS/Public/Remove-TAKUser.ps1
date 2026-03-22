<#
.SYNOPSIS
    Deletes a file-managed user from a connected TAK Server.

.DESCRIPTION
    Removes a user account via the /user-management/api/delete-user/{username}
    DELETE endpoint. This removes the account but does not revoke the user's
    certificates by default. Use -AlsoRevokeCertificates to atomically revoke all
    certificates belonging to the user before deletion, or use Remove-TAKCertificate
    separately.

.PARAMETER UserName
    The username of the account to delete. Accepts pipeline input by property name.

.PARAMETER AlsoRevokeCertificates
    When specified, revokes all certificates issued to the user via
    Get-TAKCertificate | Remove-TAKCertificate before deleting the account.

.EXAMPLE
    PS> Remove-TAKUser -UserName 'exuser1'

    Deletes the user account 'exuser1' after confirmation.

.EXAMPLE
    PS> Remove-TAKUser -UserName 'exuser1' -AlsoRevokeCertificates

    Revokes all certificates for 'exuser1', then deletes the account.

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
        [string] $UserName,

        [Parameter()]
        [switch] $AlsoRevokeCertificates
    )

    process {
        if ($PSCmdlet.ShouldProcess($UserName, 'Delete TAK user')) {
            if ($AlsoRevokeCertificates) {
                Get-TAKCertificate -UserName $UserName | Remove-TAKCertificate
            }
            $encodedName = [System.Uri]::EscapeDataString($UserName)
            $null = Invoke-TAKRequest -Path "/user-management/api/delete-user/$encodedName" -Method Delete
            Write-Verbose "Deleted TAK user: $UserName"
        }
    }
}
