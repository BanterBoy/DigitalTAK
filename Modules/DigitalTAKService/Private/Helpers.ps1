# Private helpers for DigitalTAKService module.
# These are module-scoped and not exported.

# The pm2 process name and service port are centralised here so every cmdlet
# picks them up consistently without duplicating literals.
$script:Pm2ProcessName = 'paperclip'
$script:ServicePort    = 3100

function Test-DigitalTAKPort {
    <#
    .SYNOPSIS
        Returns $true if something is listening on the DigitalTAK service port.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int] $Port = $script:ServicePort
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect('127.0.0.1', $Port)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Invoke-Pm2Command {
    <#
    .SYNOPSIS
        Runs a pm2 command and returns (exitCode, output[]).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )
    $output = & pm2 @Arguments 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Get-Pm2ProcessInfo {
    <#
    .SYNOPSIS
        Returns the pm2 JSON descriptor for the named process, or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [string] $Name = $script:Pm2ProcessName
    )
    $result = Invoke-Pm2Command -Arguments @('jlist')
    if ($result.ExitCode -ne 0) { return $null }

    try {
        $list = $result.Output | ConvertFrom-Json -ErrorAction Stop
        return $list | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    }
    catch {
        return $null
    }
}
