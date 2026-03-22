<#
.SYNOPSIS
    Gets one or all inputs configured on a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server network inputs. Without -Name, returns all inputs via
    GET /Marti/api/inputs. With -Name, returns a single input via
    GET /Marti/api/inputs/{name}.

.PARAMETER Name
    The name of a specific input to retrieve.

.EXAMPLE
    PS> Get-TAKInput

    Returns all configured inputs.

.EXAMPLE
    PS> Get-TAKInput -Name 'UDPInput'

    Returns the input named 'UDPInput'.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKInput {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName',
                   ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                $encodedName = [System.Uri]::EscapeDataString($Name)
                Invoke-TAKRequest -Path "/Marti/api/inputs/$encodedName" -Method Get
            }
            default {
                Invoke-TAKRequest -Path '/Marti/api/inputs' -Method Get
            }
        }
    }
}
