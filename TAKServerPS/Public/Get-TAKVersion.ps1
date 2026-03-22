<#
.SYNOPSIS
    Gets version information from a connected TAK Server.

.DESCRIPTION
    Retrieves the TAK Server version string and detailed build information from the
    /Marti/api/ver and /Marti/api/version/info endpoints.

.PARAMETER Detailed
    When specified, returns the full VersionInfo object including build date and git commit.
    When omitted, returns the short version string.

.EXAMPLE
    PS> Get-TAKVersion

    Returns the short version string, e.g. "5.7-RELEASE-8".

.EXAMPLE
    PS> Get-TAKVersion -Detailed

    Returns the full VersionInfo object with build details.

.OUTPUTS
    System.String
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKVersion {
    [CmdletBinding()]
    [OutputType([System.String], ParameterSetName = 'Short')]
    [OutputType([PSCustomObject], ParameterSetName = 'Detailed')]
    param (
        [Parameter(ParameterSetName = 'Detailed')]
        [switch] $Detailed
    )

    if ($Detailed) {
        Invoke-TAKRequest -Path '/Marti/api/version/info'
    }
    else {
        Invoke-TAKRequest -Path '/Marti/api/ver'
    }
}
