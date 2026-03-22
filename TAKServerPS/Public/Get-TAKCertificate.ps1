<#
.SYNOPSIS
    Gets TAK Server client certificates.

.DESCRIPTION
    Retrieves certificate records from the TAK Server certificate manager via the
    /Marti/api/certadmin/cert endpoint. Supports listing all certificates, filtering
    by username, or retrieving certificates by status (active, revoked, expired).

.PARAMETER UserName
    Filters results to certificates issued to a specific username.

.PARAMETER Active
    Returns only active (non-revoked, non-expired) certificates.

.PARAMETER Revoked
    Returns only revoked certificates.

.PARAMETER Expired
    Returns only expired certificates.

.EXAMPLE
    PS> Get-TAKCertificate

    Returns all certificates.

.EXAMPLE
    PS> Get-TAKCertificate -UserName 'fielduser1'

    Returns certificates issued to fielduser1.

.EXAMPLE
    PS> Get-TAKCertificate -Expired

    Returns all expired certificates.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
    Certificate data includes hash, subjectDn, issuanceDate, and expirationDate.
#>
function Get-TAKCertificate {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Active',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Revoked',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Expired',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(ParameterSetName = 'All')]
        [ValidateNotNullOrEmpty()]
        [string] $UserName,

        [Parameter(Mandatory, ParameterSetName = 'Active')]
        [switch] $Active,

        [Parameter(Mandatory, ParameterSetName = 'Revoked')]
        [switch] $Revoked,

        [Parameter(Mandatory, ParameterSetName = 'Expired')]
        [switch] $Expired
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Active'  { Invoke-TAKRequest -Path '/Marti/api/certadmin/cert/active' }
        'Revoked' { Invoke-TAKRequest -Path '/Marti/api/certadmin/cert/revoked' }
        'Expired' { Invoke-TAKRequest -Path '/Marti/api/certadmin/cert/expired' }
        default {
            $query = @{}
            if ($UserName) { $query['username'] = $UserName }
            Invoke-TAKRequest -Path '/Marti/api/certadmin/cert' -QueryParameters $query
        }
    }
}
