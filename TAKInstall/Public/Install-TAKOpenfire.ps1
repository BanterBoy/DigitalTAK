<#
.SYNOPSIS
    Installs Openfire XMPP Server on a Rocky Linux 9 TAK Server host via SSH.

.DESCRIPTION
    Automates the Openfire XMPP installation procedure defined in
    openfire_takChat_install.sh against a remote Rocky Linux 9 host over an
    established Posh-SSH session. Must be run after Install-TAKServer has
    completed successfully.

    Steps performed:
      1. Disable the Cockpit web console service to free port 9090.
      2. Ensure OpenJDK 17 is installed.
      3. Download the Openfire 5.0.3 RPM from the GitHub releases page.
      4. Repair /etc/init.d if it exists as a plain file instead of a directory.
      5. Install the Openfire RPM via dnf.
      6. Create a native systemd unit file for Openfire (openfire-xmpp.service).
      7. Stop any legacy Openfire process started by the init.d script.
      8. Enable and start the openfire-xmpp systemd service.
      9. Configure firewalld for all required XMPP and file-transfer ports.
     10. Optionally open the Openfire admin console ports (9090/9091).

    After this cmdlet completes, browse to http://<server-ip>:9090 and complete
    the Openfire setup wizard before connecting ATAK/WinTAK TAK Chat clients.

.PARAMETER SshSession
    An active Posh-SSH SSH session to the target Rocky Linux 9 host.

.PARAMETER OpenAdminPorts
    Open the Openfire admin console ports 9090 (HTTP) and 9091 (HTTPS) in
    firewalld. Defaults to $true. Set to $false when the admin console should
    only be accessed via an SSH tunnel or VPN.

.PARAMETER OpenFireVersion
    Openfire version string to download. Defaults to '5.0.3'. Change only if
    you need a different release; the download URL is constructed automatically.

.EXAMPLE
    PS> $sess = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
    PS> Install-TAKOpenfire -SshSession $sess

    Installs Openfire 5.0.3 with admin ports open.

.EXAMPLE
    PS> Install-TAKOpenfire -SshSession $sess -OpenAdminPorts:$false -Verbose

    Installs Openfire without exposing the admin console on the host firewall.
    Access the admin console via SSH port forwarding:
      ssh -L 9090:localhost:9090 user@server

.OUTPUTS
    None

.NOTES
    Requires the Posh-SSH module: Install-Module Posh-SSH -Scope CurrentUser
    The Openfire RPM is downloaded at runtime from GitHub with no hash
    verification (known limitation). For production use, verify the download
    integrity manually with the SHA256 published on the Openfire release page.
    Cockpit (port 9090) is disabled — if you rely on Cockpit, do not run this.
#>
function Install-TAKOpenfire {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $SshSession,

        [Parameter()]
        [bool] $OpenAdminPorts = $true,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $OpenFireVersion = '5.0.3'
    )

    if (-not $PSCmdlet.ShouldProcess($SshSession.Host, "Install Openfire $OpenFireVersion XMPP Server")) {
        return
    }

    $rpmName = "openfire-${OpenFireVersion}-1.noarch.rpm"
    $rpmUrl  = "https://github.com/igniterealtime/Openfire/releases/download/v${OpenFireVersion}/${rpmName}"
    $rpmDest = "/tmp/$rpmName"

    # ── 1. Disable Cockpit (port 9090 conflict) ────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Disabling Cockpit' -PercentComplete 8
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Disable Cockpit' -Command `
        'sudo systemctl disable --now cockpit.socket cockpit > /dev/null 2>&1 || true'

    # ── 2. Ensure Java 17 ─────────────────────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Ensuring Java 17 is installed' -PercentComplete 14
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install java-17-openjdk' -Command `
        'sudo dnf install -y java-17-openjdk'

    # ── 3. Download Openfire RPM ──────────────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status "Downloading Openfire $OpenFireVersion RPM" -PercentComplete 22
    Invoke-TAKRemoteCommand -Session $SshSession -Description "Download $rpmName" -Command `
        "curl -L -o $rpmDest '$rpmUrl'"

    # ── 4. Repair /etc/init.d if needed ──────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Checking /etc/init.d' -PercentComplete 34
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Repair /etc/init.d if it is a plain file' -Command @'
if [ -f /etc/init.d ] && [ ! -d /etc/init.d ]; then
    sudo mv /etc/init.d "/etc/init.d.bak.$(date +%Y%m%d%H%M%S)"
fi
if [ ! -e /etc/init.d ]; then
    sudo ln -s /etc/rc.d/init.d /etc/init.d
fi
'@

    # ── 5. Install Openfire RPM ───────────────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Installing Openfire RPM' -PercentComplete 42
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install Openfire' -Command `
        "sudo dnf install -y $rpmDest"

    # ── 6. Create native systemd unit ─────────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Creating systemd unit' -PercentComplete 54

    # Use a heredoc written via sudo tee.
    $systemdUnit = @'
[Unit]
Description=Openfire XMPP Server
After=network.target

[Service]
Type=simple
User=daemon
Group=daemon
WorkingDirectory=/opt/openfire
Environment=OPENFIRE_HOME=/opt/openfire
ExecStart=/bin/bash -lc 'export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")"); exec /opt/openfire/bin/openfire.sh'
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
'@
    # Write unit file via SSH heredoc
    $escapedUnit = $systemdUnit.Replace("'", "'\\''")
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Write openfire-xmpp.service unit' -Command `
        "printf '%s\n' '$escapedUnit' | sudo tee /etc/systemd/system/openfire-xmpp.service > /dev/null"

    # ── 7. Stop legacy init.d Openfire process ────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Stopping legacy Openfire processes' -PercentComplete 62
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Stop legacy init.d Openfire' -Command `
        "sudo /etc/init.d/openfire stop > /dev/null 2>&1 || true; sudo pkill -f '/opt/openfire/lib/startup.jar' || true; sleep 2" -AllowFailure

    # ── 8. Enable and start openfire-xmpp ────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Starting Openfire service' -PercentComplete 70
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Reload systemd and enable Openfire' -Command `
        'sudo systemctl daemon-reload && sudo systemctl enable --now openfire-xmpp.service'

    Wait-TAKServiceReady -Session $SshSession -ServiceName 'openfire-xmpp' -TimeoutSeconds 120

    # ── 9. Firewall — Openfire ports ──────────────────────────────────────
    Write-Progress -Activity 'Installing Openfire' -Status 'Configuring firewall' -PercentComplete 82
    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Ensure firewalld is running' -Command `
        'sudo systemctl enable --now firewalld'

    $ports = @(
        '8089/tcp'   # TAK Server secure CoT (TLS)
        '8443/tcp'   # TAK Server HTTPS
        '8446/tcp'   # TAK Server cert enrollment
        '5222/tcp'   # XMPP client-to-server (STARTTLS)
        '5223/tcp'   # XMPP client-to-server (Direct TLS)
        '5269/tcp'   # XMPP server-to-server (federation)
        '7070/tcp'   # Openfire HTTP binding
        '7443/tcp'   # Openfire HTTPS binding
        '7777/tcp'   # Openfire file transfer proxy
        '8080/udp'   # CoT over UDP/QUIC (ATAK 4.6+)
    )

    foreach ($port in $ports) {
        Invoke-TAKRemoteCommand -Session $SshSession -Description "Open $port" -Command `
            "sudo firewall-cmd --zone=public --permanent --add-port=$port"
    }

    if ($OpenAdminPorts) {
        foreach ($adminPort in @('9090/tcp', '9091/tcp')) {
            Invoke-TAKRemoteCommand -Session $SshSession -Description "Open Openfire admin port $adminPort" -Command `
                "sudo firewall-cmd --zone=public --permanent --add-port=$adminPort"
        }
    }

    Invoke-TAKRemoteCommand -Session $SshSession -Description 'Reload firewall' -Command `
        'sudo firewall-cmd --reload'

    Write-Progress -Activity 'Installing Openfire' -Completed
    Write-Verbose 'Openfire installation complete.'
    Write-Verbose 'Browse to http://<server-ip>:9090 to complete the Openfire setup wizard.'
    Write-Verbose 'XMPP domain must match the hostname/IP your ATAK clients will use.'
}
