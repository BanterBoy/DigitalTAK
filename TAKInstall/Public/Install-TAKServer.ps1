<#
.SYNOPSIS
    Installs TAK Server 5.7-RELEASE8 on a Rocky Linux 9 host via SSH.

.DESCRIPTION
    Automates the full TAK Server installation procedure defined in
    RL9_tak5.7r8_install.sh against a remote Rocky Linux 9 host over an
    established Posh-SSH session.

    Steps performed:
      1. Raise the open-files ulimit in /etc/security/limits.conf.
      2. Install dnf-plugins-core, vim, and EPEL.
      3. Add the PostgreSQL PGDG repository and disable the built-in module.
      4. Install OpenJDK 17 and enable the CRB (CodeReady Builder) repo.
      5. Upload the TAK RPM (and optional GPG key) to the remote host.
      6. Optionally verify the RPM GPG signature before installation.
      7. Install the TAK Server RPM via dnf.
      8. Install checkpolicy, apply the TAK SELinux policy, and verify the module.
      9. Enable and start the takserver systemd service.
     10. Install firewalld and open ports 8089, 8443, and 8446.
     11. Copy createTakCerts.sh and takUserCreateCerts_doNotRunAsRoot.sh to
         /opt/tak/certs and make them executable.

    After this cmdlet completes, run New-TAKServerCertificate followed by
    Set-TAKAdminCertificate to complete the initial setup.

.PARAMETER SshSession
    An active Posh-SSH SSH session to the target Rocky Linux 9 host.
    Create one with: $session = New-SSHSession -ComputerName <ip> -Credential <cred>

.PARAMETER RpmPath
    Local path to the TAK Server RPM file (takserver-5.7-RELEASE8.noarch.rpm).
    The file is uploaded to the remote host via SCP before installation.

.PARAMETER GpgKeyPath
    Optional local path to the TAK Server GPG signing key (takserver-public-gpg.key).
    When provided alongside -RpmPath, the RPM signature is verified before installation.

.PARAMETER RemoteWorkDir
    Directory on the remote host to upload files to. Created if it does not
    exist. Defaults to /tmp/tak_install.

.PARAMETER SkipGpgVerification
    Skip GPG signature verification even when -GpgKeyPath is provided.

.EXAMPLE
    PS> $sess = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
    PS> Install-TAKServer -SshSession $sess -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm'

    Installs TAK Server on the remote host, uploading the RPM first.

.EXAMPLE
    PS> Install-TAKServer -SshSession $sess `
            -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' `
            -GpgKeyPath '.\takserver-public-gpg.key' `
            -Verbose

    Installs with GPG signature verification and verbose step output.

.OUTPUTS
    None

.NOTES
    Requires the Posh-SSH module: Install-Module Posh-SSH -Scope CurrentUser
    Target platform: Rocky Linux 9.x (dnf, SELinux, firewalld).
    Run as a user with sudo privileges on the remote host.
    The RPM file must be obtained from tak.gov.
#>
function Install-TAKServer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $SshSession,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $RpmPath,

        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $GpgKeyPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RemoteWorkDir = '/tmp/tak_install',

        [Parameter()]
        [switch] $SkipGpgVerification,

        [Parameter()]
        [PSCredential] $Credential
    )

    if (-not $PSCmdlet.ShouldProcess($SshSession.Host, 'Install TAK Server 5.7-RELEASE8')) {
        return
    }

    $rpmFile = Split-Path $RpmPath -Leaf

    # ── 1. Raise open-files ulimit ───────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Configuring system limits' -PercentComplete 5
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Raise nofile ulimit' -Command `
        'if ! sudo grep -qE "^\*\s+soft\s+nofile\s+32768\$" /etc/security/limits.conf; then printf "* soft nofile 32768\n* hard nofile 32768\n" | sudo tee --append /etc/security/limits.conf > /dev/null; fi'

    # ── 2. EPEL and base packages ─────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Installing EPEL and base packages' -PercentComplete 10
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install dnf-plugins-core, vim, epel-release' -Command `
        'sudo dnf install -y dnf-plugins-core vim epel-release'

    # ── 3. PostgreSQL PGDG repo ───────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Adding PostgreSQL PGDG repository' -PercentComplete 20
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install PostgreSQL PGDG repo' -Command `
        "sudo dnf --disablerepo='*' -y --nogpgcheck install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Disable built-in postgresql module' -Command `
        'sudo dnf -qy module disable postgresql'

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Update system packages' -Command `
        'sudo dnf update -y' -TimeOut 600

    # ── 4. Java 17 + CRB ─────────────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Installing OpenJDK 17' -PercentComplete 30
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install OpenJDK 17' -Command `
        'sudo dnf install -y java-17-openjdk-devel' -TimeOut 600

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Enable CRB repo' -Command `
        'sudo dnf config-manager --set-enabled crb'

    # ── 5. Upload files via SCP ───────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Uploading RPM to remote host' -PercentComplete 38

    Invoke-TAKRemoteCommand -Session $SshSession -Description "Create remote work dir $RemoteWorkDir" -Command `
        "sudo mkdir -p $RemoteWorkDir && sudo chown `$(whoami) $RemoteWorkDir && chmod 700 $RemoteWorkDir"

    # Upload via SCP (requires credential for Posh-SSH 3.x which does not support session reuse)
    if (-not $Credential) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new(
                'The -Credential parameter is required for file upload. Provide the same PSCredential used to create the SSH session.'),
            'TAKCredentialRequired',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "  => SCP upload: $rpmFile -> $RemoteWorkDir/"
    Set-SCPItem -ComputerName $SshSession.Host -Credential $Credential -Path $RpmPath `
        -Destination "$RemoteWorkDir/" -AcceptKey -Force -OperationTimeout 600 -ErrorAction Stop

    $remoteRpm = "$RemoteWorkDir/$rpmFile"
    $remoteGpg = ''

    if ($GpgKeyPath -and -not $SkipGpgVerification) {
        $gpgFile = Split-Path $GpgKeyPath -Leaf
        Write-Verbose "  => SCP upload: $gpgFile -> $RemoteWorkDir/"
        Set-SCPItem -ComputerName $SshSession.Host -Credential $Credential -Path $GpgKeyPath `
            -Destination "$RemoteWorkDir/" -AcceptKey -Force -ErrorAction Stop
        $remoteGpg = "$RemoteWorkDir/$gpgFile"
    }

    # ── 6. GPG verification (optional) ───────────────────────────────────────
    if ($remoteGpg) {
        Write-Progress -Activity 'Installing TAK Server' -Status 'Verifying RPM GPG signature' -PercentComplete 42
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Import GPG key' -Command `
            "sudo rpm --import $remoteGpg"
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Verify RPM signature' -Command `
            "rpm --checksig $remoteRpm"
    }

    # ── 7. Install TAK RPM ────────────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Installing TAK Server RPM' -PercentComplete 48
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install takserver RPM' -Command `
        "sudo dnf install -y $remoteRpm" -TimeOut 600

    # ── 8. SELinux policy ─────────────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Applying SELinux policy' -PercentComplete 60
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install checkpolicy' -Command `
        'sudo dnf install -y checkpolicy'

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Apply TAK SELinux policy' -Command `
        'cd /opt/tak && sudo ./apply-selinux.sh && sudo semodule -l | grep takserver'

    # ── 9. Enable and start takserver ─────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Starting takserver service' -PercentComplete 70
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'daemon-reload' -Command `
        'sudo systemctl daemon-reload'

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Enable + start takserver' -Command `
        'sudo systemctl enable --now takserver'

    Wait-TAKServiceReady -Session $SshSession -ServiceName 'takserver' -TimeoutSeconds 120

    # ── 10. Firewalld ─────────────────────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Configuring firewall' -PercentComplete 82
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install and enable firewalld' -Command `
        'sudo dnf install -y firewalld && sudo systemctl enable --now firewalld'

    foreach ($portProto in @('8089/tcp', '8443/tcp', '8446/tcp', '8090/udp')) {
        Invoke-TAKRemoteCommand -Session $SshSession -Description "Open port $portProto" -Command `
            "sudo firewall-cmd --zone=public --permanent --add-port=$portProto"
    }

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Reload firewall' -Command `
        'sudo firewall-cmd --reload'

    # ── 11. Deploy cert helper scripts ────────────────────────────────────────
    Write-Progress -Activity 'Installing TAK Server' -Status 'Deploying certificate helper scripts' -PercentComplete 92
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Copy cert scripts to /opt/tak/certs' -Command @"
sudo cp $RemoteWorkDir/createTakCerts.sh /opt/tak/certs/ 2>/dev/null || true
sudo cp $RemoteWorkDir/takUserCreateCerts_doNotRunAsRoot.sh /opt/tak/certs/ 2>/dev/null || true
sudo cp $RemoteWorkDir/utils.sh /opt/tak/certs/ 2>/dev/null || true
sudo chmod +x /opt/tak/certs/createTakCerts.sh 2>/dev/null || true
sudo chmod +x /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh 2>/dev/null || true
"@

    # Clean up temp files
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Remove remote work dir' -Command `
        "sudo rm -rf $RemoteWorkDir" -AllowFailure

    Write-Progress -Activity 'Installing TAK Server' -Completed
    Write-Verbose 'TAK Server installation complete.'
    Write-Verbose "Next: Run New-TAKServerCertificate, then Set-TAKAdminCertificate."
}
