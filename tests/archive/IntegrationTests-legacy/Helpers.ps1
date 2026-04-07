#Requires -Version 7.0
<#
.SYNOPSIS
    Shared configuration and helper functions for DigitalTAK integration tests.

.DESCRIPTION
    Loads integration environment from environment variables and provides
    helper functions used across all integration test files.

    Required environment variables:
        TAK_INTEGRATION_HOST  - IP address or hostname of the running TAK Server VM

    Optional environment variables:
        TAK_SSH_USER          - SSH username (default: atak)
        TAK_SSH_PASS          - SSH password in plain text
        TAK_VM_NAME           - Hyper-V VM name (default: TAKServer)
        TAK_CERT_PASS         - PKCS#12 certificate password (default: atakatak)
        TAK_API_PORT          - TAK Server HTTPS API port (default: 8443)
        TAK_ENROLL_PORT       - Certificate enrollment port (default: 8446)
        TAK_COT_PORT          - Cursor-on-Target TCP port (default: 8089)

.EXAMPLE
    # Set environment, then run all integration tests:
    $env:TAK_INTEGRATION_HOST = '192.168.1.50'
    $env:TAK_SSH_USER         = 'atak'
    $env:TAK_SSH_PASS         = '<SshPassword>'
    Invoke-Pester ./IntegrationTests -Output Detailed
#>

function Get-TAKIntegrationConfig {
    <#
    .SYNOPSIS
        Returns a hashtable of integration test configuration values.
        Returns $null if TAK_INTEGRATION_HOST is not set.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $host_ = $env:TAK_INTEGRATION_HOST
    if ([string]::IsNullOrWhiteSpace($host_)) {
        return $null
    }

    return @{
        Host        = $host_.Trim()
        SshUser     = if ($env:TAK_SSH_USER)   { $env:TAK_SSH_USER }   else { 'atak' }
        SshPass     = $env:TAK_SSH_PASS
        VMName      = if ($env:TAK_VM_NAME)    { $env:TAK_VM_NAME }    else { 'TAKServer' }
        CertPass    = if ($env:TAK_CERT_PASS)  { $env:TAK_CERT_PASS }  else { 'atakatak' }
        ApiPort     = if ($env:TAK_API_PORT)   { [int]$env:TAK_API_PORT }   else { 8443 }
        EnrollPort  = if ($env:TAK_ENROLL_PORT){ [int]$env:TAK_ENROLL_PORT } else { 8446 }
        CotPort     = if ($env:TAK_COT_PORT)   { [int]$env:TAK_COT_PORT }   else { 8089 }
    }
}

function New-TAKIntegrationSSHSession {
    <#
    .SYNOPSIS
        Opens a Posh-SSH session to the TAK Server VM.
        Caller is responsible for closing via Remove-SSHSession.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Config
    )

    if (-not $Config.SshPass) {
        throw 'TAK_SSH_PASS is not set. Set this env var to the SSH user password before running integration tests.'
    }

    $secPw   = ConvertTo-SecureString $Config.SshPass -AsPlainText -Force
    $cred    = [System.Management.Automation.PSCredential]::new($Config.SshUser, $secPw)
    $session = New-SSHSession -ComputerName $Config.Host -Credential $cred -AcceptKey -Force -ErrorAction Stop
    return $session
}

function Invoke-TAKSSHCommand {
    <#
    .SYNOPSIS
        Runs a single bash command on the TAK Server via an open SSH session.
        Returns a PSCustomObject with Output (string), ExitStatus (int).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Session,

        [Parameter(Mandatory)]
        [string] $Command
    )

    $result = Invoke-SSHCommand -SessionId $Session.SessionId -Command $Command -ErrorAction Stop
    return [PSCustomObject]@{
        Output     = ($result.Output -join "`n").Trim()
        ExitStatus = $result.ExitStatus
    }
}

function Test-TAKTCPPort {
    <#
    .SYNOPSIS
        Returns $true if the given TCP port is open on the TAK Server host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Host,

        [Parameter(Mandatory)]
        [int] $Port,

        [int] $TimeoutMs = 3000
    )

    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($Host, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        $tcp.Close()
        return $ok
    }
    catch {
        return $false
    }
}

Export-ModuleMember -Function *
