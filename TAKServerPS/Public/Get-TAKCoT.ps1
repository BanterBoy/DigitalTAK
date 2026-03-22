<#
.SYNOPSIS
    Gets Cursor-on-Target (CoT) events from a connected TAK Server.

.DESCRIPTION
    Retrieves CoT situational awareness data from TAK Server.

    - Default (no parameters): returns the current SA track for all contacts
      via GET /Marti/api/cot/sa.
    - ByUid: returns the CoT XML for a specific UID via
      GET /Marti/api/cot/xml/{uid}.

.PARAMETER Uid
    The CoT UID of a specific contact or entity to retrieve.

.EXAMPLE
    PS> Get-TAKCoT

    Returns the current SA track for all contacts.

.EXAMPLE
    PS> Get-TAKCoT -Uid 'ANDROID-abc123'

    Returns the CoT XML for the specified UID.

.OUTPUTS
    PSCustomObject  (SA mode)
    string          (ByUid XML mode)

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKCoT {
    [CmdletBinding(DefaultParameterSetName = 'SA')]
    [OutputType([PSCustomObject], ParameterSetName = 'SA')]
    [OutputType([string], ParameterSetName = 'ByUid')]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByUid',
                   ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByUid' {
                $encodedUid = [System.Uri]::EscapeDataString($Uid)
                Invoke-TAKRequest -Path "/Marti/api/cot/xml/$encodedUid" -Method Get
            }
            default {
                Invoke-TAKRequest -Path '/Marti/api/cot/sa' -Method Get
            }
        }
    }
}
