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

        Transient failures (network errors, HTTP 429/503) are retried up to RetryCount
        times with a configurable delay.

        When -AutoPage is specified and the response contains a .data array, the
        function automatically pages through all results using TAK's offset/limit
        pattern and returns the combined collection.

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

    .PARAMETER RetryCount
        Number of retry attempts on transient failures (HttpRequestException or HTTP
        429/503). Defaults to 2. Set to 0 to disable retries.

    .PARAMETER RetryDelaySeconds
        Seconds to wait between retry attempts. Defaults to 3.

    .PARAMETER AutoPage
        When specified, automatically pages through all results for list endpoints
        that return a TAK ApiResponse wrapper with a .data array, using TAK's
        offset/limit query parameters (default page size: 100).
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
        [switch] $Raw,

        [Parameter()]
        [ValidateRange(0, 5)]
        [int] $RetryCount = 2,

        [Parameter()]
        [ValidateRange(1, 30)]
        [int] $RetryDelaySeconds = 3,

        [Parameter()]
        [switch] $AutoPage
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

    # ── AutoPage: collect all pages and return combined result ────────────────
    if ($AutoPage) {
        $pageSize   = 100
        $offset     = 0
        $allResults = [System.Collections.Generic.List[object]]::new()

        do {
            $pagedQuery = @{ limit = $pageSize; offset = $offset }
            if ($QueryParameters) {
                foreach ($k in $QueryParameters.Keys) { $pagedQuery[$k] = $QueryParameters[$k] }
            }
            $page = Invoke-TAKRequest -Path $Path -Method $Method -QueryParameters $pagedQuery `
                        -Body $Body -ContentType $ContentType `
                        -RetryCount $RetryCount -RetryDelaySeconds $RetryDelaySeconds

            # $page is already the unwrapped .data array (or array-like object)
            if ($null -ne $page) {
                $pageArray = @($page)
                $allResults.AddRange($pageArray)
                $offset += $pageSize
            }
            else {
                break
            }
        } while ($pageArray.Count -ge $pageSize)

        return $allResults.ToArray()
    }

    # ── Build URI ─────────────────────────────────────────────────────────────
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

    # ── Invoke with retry ─────────────────────────────────────────────────────
    $attempt   = 0
    $lastError = $null

    do {
        try {
            $response  = Invoke-RestMethod @irmParams
            $lastError = $null
            break
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            $statusCode = [int]$PSItem.Exception.Response.StatusCode
            if ($statusCode -in 429, 503 -and $attempt -lt $RetryCount) {
                $attempt++
                Write-Verbose "[TAKRequest] HTTP $statusCode — attempt $attempt of $RetryCount. Retrying in ${RetryDelaySeconds}s..."
                Start-Sleep -Seconds $RetryDelaySeconds
                $lastError = $PSItem
            }
            else {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }
        catch [System.Net.Http.HttpRequestException] {
            if ($attempt -lt $RetryCount) {
                $attempt++
                Write-Verbose "[TAKRequest] Network error — attempt $attempt of $RetryCount. Retrying in ${RetryDelaySeconds}s..."
                Start-Sleep -Seconds $RetryDelaySeconds
                $lastError = $PSItem
            }
            else {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $PSItem.Exception,
                    'TAKHttpError',
                    [System.Management.Automation.ErrorCategory]::ConnectionError,
                    $uriBuilder.Uri
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    } while ($attempt -le $RetryCount)

    if ($lastError) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $lastError.Exception,
            'TAKHttpError',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $uriBuilder.Uri
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # ── Unwrap TAK ApiResponse wrapper when .data is present ──────────────────
    if (-not $Raw -and $null -ne $response -and
        ($response.PSObject.Properties.Name -contains 'data')) {
        return $response.data
    }
    return $response
}
