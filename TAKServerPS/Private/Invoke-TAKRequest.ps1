function Invoke-TAKRequest {
    <#
    .SYNOPSIS
        Internal helper that sends authenticated HTTP requests to a connected TAK Server.

    .DESCRIPTION
        Builds the full URI from the active session base URL, applies the stored
        authentication (certificate, bearer token, or Basic credential), and calls
        Invoke-RestMethod. Unwraps the standard TAK ApiResponse wrapper
        ({ version, type, nodeId, data }) and returns the inner .data value unless
        -Raw is specified.

        This function is private. Use Connect-TAKServer to establish a session before
        calling any public cmdlet.

    .PARAMETER Path
        The API path relative to the base URL, e.g. '/Marti/api/version/info'.

    .PARAMETER Method
        HTTP method. Defaults to Get.

    .PARAMETER QueryParameters
        Hashtable of query-string key/value pairs. Null values are omitted.

    .PARAMETER Body
        Object to serialise as JSON request body.

    .PARAMETER ContentType
        Content-Type header for the request body. Defaults to 'application/json'.

    .PARAMETER Raw
        When specified, returns the full response object instead of unwrapping .data.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebRequestMethod] $Method = 'Get',

        [Parameter()]
        [hashtable] $QueryParameters,

        [Parameter()]
        [object] $Body,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ContentType = 'application/json',

        [Parameter()]
        [switch] $Raw
    )

    if (-not $script:TAKSession) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                'Not connected to a TAK Server. Run Connect-TAKServer first.'
            ),
            'TAKNotConnected',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # Build URI
    $uriString = $script:TAKSession.BaseUrl.TrimEnd('/') + $Path
    $uriBuilder = [System.UriBuilder]::new($uriString)

    if ($QueryParameters -and $QueryParameters.Count -gt 0) {
        $queryParts = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $QueryParameters.Keys) {
            if ($null -ne $QueryParameters[$key]) {
                $encodedKey   = [System.Uri]::EscapeDataString($key)
                $encodedValue = [System.Uri]::EscapeDataString([string]$QueryParameters[$key])
                $queryParts.Add("$encodedKey=$encodedValue")
            }
        }
        if ($queryParts.Count -gt 0) {
            $uriBuilder.Query = $queryParts -join '&'
        }
    }

    $irmParams = @{
        Uri         = $uriBuilder.Uri
        Method      = $Method
        ErrorAction = 'Stop'
    }

    # Authentication priority: Certificate > Token > Credential
    if ($script:TAKSession.Certificate) {
        $irmParams['Certificate'] = $script:TAKSession.Certificate
    }
    elseif ($script:TAKSession.Token) {
        $irmParams['Authentication'] = 'Bearer'
        $irmParams['Token']          = $script:TAKSession.Token
    }
    elseif ($script:TAKSession.Credential) {
        $irmParams['Authentication'] = 'Basic'
        $irmParams['Credential']     = $script:TAKSession.Credential
    }

    if ($script:TAKSession.SkipCertCheck) {
        $irmParams['SkipCertificateCheck'] = $true
    }

    if ($null -ne $Body) {
        $irmParams['Body']        = ($Body | ConvertTo-Json -Depth 20 -Compress)
        $irmParams['ContentType'] = $ContentType
    }

    try {
        $response = Invoke-RestMethod @irmParams
    }
    catch [System.Net.Http.HttpRequestException] {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $PSItem.Exception,
            'TAKHttpError',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $uriBuilder.Uri
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    # Unwrap TAK ApiResponse wrapper when .data is present
    if (-not $Raw -and $null -ne $response -and
        ($response.PSObject.Properties.Name -contains 'data')) {
        return $response.data
    }
    return $response
}
