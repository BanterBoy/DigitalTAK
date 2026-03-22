<#
.SYNOPSIS
    Revokes or removes API tokens on a connected TAK Server.

.DESCRIPTION
    Removes API tokens from TAK Server. Two parameter sets are available:

    - ByToken: deletes an individual token via DELETE /Marti/api/token/{token}.
    - Revoke:  bulk-revokes one or more tokens via
               DELETE /Marti/api/token/revoke/{tokens} (comma-separated).

.PARAMETER Token
    A single token string to delete.

.PARAMETER Tokens
    One or more token strings to revoke in bulk.

.EXAMPLE
    PS> Remove-TAKToken -Token 'eyJhbGciOi...'

    Removes a single API token.

.EXAMPLE
    PS> Remove-TAKToken -Tokens 'token1','token2','token3'

    Bulk-revokes three tokens in one request.

.OUTPUTS
    None

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Remove-TAKToken {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByToken')]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByToken',
                   ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Token,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Revoke')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Tokens
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByToken' {
                if ($PSCmdlet.ShouldProcess($Token, 'Delete TAK API token')) {
                    $encodedToken = [System.Uri]::EscapeDataString($Token)
                    Invoke-TAKRequest -Path "/Marti/api/token/$encodedToken" -Method Delete | Out-Null
                }
            }
            'Revoke' {
                $joined = $Tokens -join ','
                if ($PSCmdlet.ShouldProcess("$($Tokens.Count) token(s)", 'Revoke TAK API tokens')) {
                    $encodedTokens = [System.Uri]::EscapeDataString($joined)
                    Invoke-TAKRequest -Path "/Marti/api/token/revoke/$encodedTokens" -Method Delete | Out-Null
                }
            }
        }
    }
}
