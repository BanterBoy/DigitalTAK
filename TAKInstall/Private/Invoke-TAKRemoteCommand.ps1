<#
.SYNOPSIS
    Executes a command on a remote TAK Server host via SSH.

.DESCRIPTION
    Internal helper used by all TAKInstall public cmdlets. Wraps Invoke-SSHCommand
    from the Posh-SSH module. Throws a terminating error if the remote command
    exits with a non-zero status code, unless -AllowFailure is set.

.PARAMETER Session
    An active Posh-SSH SSH session (from New-SSHSession).

.PARAMETER Command
    The bash command string to execute on the remote host.

.PARAMETER Description
    Optional human-readable description written to verbose output.

.PARAMETER AllowFailure
    When set, a non-zero exit code does not throw; the result object is returned.
#>
function Invoke-TAKRemoteCommand {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $Session,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Command,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Description,

        [Parameter()]
        [switch] $AllowFailure,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [int] $TimeOut = 0
    )

    if ($Description) {
        Write-Verbose "  => $Description"
    }

    $sshParams = @{
        SSHSession = $Session
        Command    = $Command
    }
    if ($TimeOut -gt 0) {
        $sshParams['TimeOut'] = $TimeOut
    }

    $result = Invoke-SSHCommand @sshParams

    if ($result.ExitStatus -ne 0 -and -not $AllowFailure) {
        $msg = "Remote command failed (exit $($result.ExitStatus))"
        if ($Description) { $msg += ": $Description" }
        $msg += "`nCommand: $Command"
        if ($result.Error) { $msg += "`nStderr:  $($result.Error)" }

        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($msg),
            'TAKRemoteCommandFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Command
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $result
}
