#!/bin/bash
## Openfire XMPP Server + TAK Chat Addendum
## Run AFTER RL9_tak5.7r8_install.sh has completed successfully.
## Installs Openfire 5.0.3, configures firewall ports, and provides setup guidance for TAK Chat.
## All install files are expected to be located in /atakciv.

## Ryan Schilder - March 2024

set -euo pipefail

# Set OPENFIRE_OPEN_ADMIN_PORTS=false to keep 9090/9091 closed on host firewall.
OPENFIRE_OPEN_ADMIN_PORTS="${OPENFIRE_OPEN_ADMIN_PORTS:-true}"

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ DISABLE COCKPIT (port 9090 conflict) +"
echo "++++++++++++++++++++++++++++++++++++++++++++"

# Rocky Linux ships with Cockpit (web system console) which binds to port 9090 by default.
# This directly conflicts with the Openfire admin console on the same port.
# Cockpit is not needed on this server (administration is done via SSH), so disable it.
echo "Stopping and disabling Cockpit to free port 9090..."
sudo systemctl disable --now cockpit.socket cockpit >/dev/null 2>&1 || true
echo "Cockpit disabled."

echo "++++++++++++++++++++++++++++++++++++++++++++"


echo "++++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL OPENFIRE XMPP +++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

# Java 17 is installed by RL9.5_tak5.4r14_install.sh; this ensures it is present
# if this script is run standalone.
# curl is used for the download as it is installed by default on Rocky Linux 9.
echo "Ensuring Java 17 is installed..."
sudo dnf install -y java-17-openjdk

# OPENFIRE_RPM_SHA256: expected SHA-256 hash of the Openfire 5.0.3 RPM.
# Obtain the authoritative value from the release page:
#   https://github.com/igniterealtime/Openfire/releases/tag/v5.0.3
# Set this variable (or export it before running the script) to enable checksum
# verification. Leave empty to skip (NOT recommended for production).
OPENFIRE_RPM_SHA256="${OPENFIRE_RPM_SHA256:-}"

echo "Downloading Openfire 5.0.3 RPM from GitHub releases..."
curl -fL -o /atakciv/openfire-5.0.3-1.noarch.rpm \
    "https://github.com/igniterealtime/Openfire/releases/download/v5.0.3/openfire-5.0.3-1.noarch.rpm"

if [ -n "$OPENFIRE_RPM_SHA256" ]; then
    echo "Verifying Openfire RPM checksum..."
    echo "$OPENFIRE_RPM_SHA256  /atakciv/openfire-5.0.3-1.noarch.rpm" | sha256sum --check
    echo "Checksum verified."
else
    echo "WARNING: OPENFIRE_RPM_SHA256 is not set. Skipping checksum verification."
    echo "         Set this variable to the expected SHA-256 for production deployments."
fi

echo "Installing Openfire..."
# Openfire's RPM expects /etc/init.d to exist as a directory/symlink target.
# On a healthy Rocky Linux system this is typically a symlink to /etc/rc.d/init.d.
# If /etc/init.d exists as a file, the RPM install will fail and we must repair it.
if [ -f /etc/init.d ]; then
    echo "/etc/init.d exists as a file. Backing it up and restoring the expected symlink..."
    sudo mv /etc/init.d "/etc/init.d.bak.$(date +%Y%m%d%H%M%S)"
fi

if [ ! -e /etc/init.d ]; then
    sudo ln -s /etc/rc.d/init.d /etc/init.d
fi

if [ ! -d /etc/init.d ]; then
    echo "ERROR: /etc/init.d is not a directory after repair attempt."
    exit 1
fi

sudo dnf install -y /atakciv/openfire-5.0.3-1.noarch.rpm

echo "Creating native systemd unit for Openfire..."
sudo tee /etc/systemd/system/openfire-xmpp.service > /dev/null <<'EOF'
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
EOF

echo "Cleaning up any legacy Openfire process..."
sudo /etc/init.d/openfire stop >/dev/null 2>&1 || true
sudo pkill -f '/opt/openfire/lib/startup.jar' || true
sleep 2

echo "Enabling and starting Openfire service..."
sudo systemctl daemon-reload
sudo systemctl enable --now openfire-xmpp.service
sudo systemctl status openfire-xmpp.service --no-pager -l

echo "++++++++++++++++++++++++++++++++++++++++++"


echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ TAK CHAT OPENFIRE PLUGIN ++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

# Openfire itself provides the XMPP service used by TAK Chat clients.
# No additional TAK.gov JAR is required by this addendum.
# If you have a separate Openfire plugin from another source, deploy it manually
# after validating that it matches your Openfire version and trust requirements.
echo "Openfire provides the XMPP service for TAK Chat clients."
echo "No additional TAK.gov plugin JAR is installed by this script."

echo "++++++++++++++++++++++++++++++++++++++++++"


echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ CONFIGURE FIREWALL ++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

sudo systemctl enable --now firewalld

# TAK Server ports - these should already be open from RL9.5_tak5.4r14_install.sh.
# --permanent is idempotent so re-adding them is safe.
echo "Ensuring TAK Server ports are open..."
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp   # Secure CoT (TLS, client cert)
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp   # HTTPS Web UI / REST API
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp   # Certificate enrolment / user auth

# Openfire / XMPP ports
echo "Opening Openfire XMPP ports..."
sudo firewall-cmd --zone=public --permanent --add-port=5222/tcp   # XMPP client-to-server (STARTTLS)
sudo firewall-cmd --zone=public --permanent --add-port=5223/tcp   # XMPP client-to-server (Direct TLS, legacy clients)
sudo firewall-cmd --zone=public --permanent --add-port=5269/tcp   # XMPP server-to-server (optional federation)

# Optional QUIC/UDP port for ATAK 4.6+ clients
sudo firewall-cmd --zone=public --permanent --add-port=8080/udp   # CoT over UDP/QUIC (ATAK 4.6+, optional)

# Openfire web binding ports (websocket and BOSH for web clients)
echo "Opening Openfire web binding ports..."
sudo firewall-cmd --zone=public --permanent --add-port=7070/tcp   # Web Binding HTTP (websocket/BOSH)
sudo firewall-cmd --zone=public --permanent --add-port=7443/tcp   # Web Binding HTTPS (websocket/BOSH)

# Openfire file transfer proxy port
echo "Opening Openfire file transfer port..."
sudo firewall-cmd --zone=public --permanent --add-port=7777/tcp   # File Transfer Proxy

# Openfire admin console ports are optional.
# Use OPENFIRE_OPEN_ADMIN_PORTS=false to keep these closed on host firewall.
if [ "$OPENFIRE_OPEN_ADMIN_PORTS" = "true" ]; then
    echo "Opening Openfire admin console ports..."
    sudo firewall-cmd --zone=public --permanent --add-port=9090/tcp   # Openfire Admin Console HTTP
    sudo firewall-cmd --zone=public --permanent --add-port=9091/tcp   # Openfire Admin Console HTTPS
else
    echo "Leaving Openfire admin console ports closed (OPENFIRE_OPEN_ADMIN_PORTS=false)."
fi

sudo firewall-cmd --reload

echo "Active firewall rules:"
sudo firewall-cmd --zone=public --list-all

echo "++++++++++++++++++++++++++++++++++++++++++"


echo ""
echo "=== OPENFIRE INITIAL SETUP INSTRUCTIONS ==="
echo ""
echo "1. From your admin machine, browse to:"
echo "     http://<server-ip>:9090"
echo "   and complete the Openfire setup wizard."
echo ""
echo "2. XMPP Domain: set this to the hostname or IP your ATAK clients will use to connect."
echo "   It must match exactly - changing it later requires a reset."
echo ""
echo "3. Admin account: set a strong, unique password. Do NOT use 'admin', 'openfire', or 'atakatak'."
echo ""
echo "4. DATABASE:"
echo "   - Embedded Derby DB is acceptable for testing and small deployments only."
echo "   - It does NOT support concurrent load well and has no backup tooling."
echo "   - For any operational or production use, configure an external PostgreSQL or MySQL database."
echo ""
echo "5. After setup is complete:"
echo "   - Switch the admin console to HTTPS only (Admin Console -> Server -> Server Settings)."
echo "   - Close port 9090 (HTTP) once you have confirmed HTTPS (9091) is working."
echo ""
echo "6. Create XMPP user accounts for each ATAK/WinTAK operator:"
echo "   Admin Console -> Users/Groups -> Create New User"
echo "   Operators enter these credentials in the ATAK TAK Chat plugin."
echo ""
echo "=== CLIENT SETUP ==="
echo ""
echo "- ATAK/WinTAK TAK Chat plugin: point to this server on port 5222 (STARTTLS)"
echo "  or 5223 (Direct TLS for older clients)."
echo "- Ensure clients trust the server certificate:"
echo "    Self-signed: distribute the server CA cert to each device."
echo "- TAK Server CoT: clients connect on port 8089 using their client .p12 certificate"
echo "  (created by createTakCerts.sh / takUserCreateCerts_doNotRunAsRoot.sh)."
echo ""
echo "=== REQUIRED PORTS REFERENCE ==="
echo ""
echo "Port       Proto  Purpose"
echo "--------   -----  -------------------------------------------------------"
echo "8089       tcp    TAK Server secure CoT (TLS, client cert required)"
echo "8443       tcp    TAK Server HTTPS (Web UI, REST API, data packages)"
echo "8446       tcp    TAK Server HTTPS (certificate enrolment / user auth)"
echo "5222       tcp    Openfire XMPP client-to-server (STARTTLS)"
echo "5223       tcp    Openfire XMPP client-to-server (Direct TLS, legacy clients)"
echo "5269       tcp    Openfire XMPP server-to-server (optional federation only)"
echo "7070       tcp    Openfire Web Binding HTTP (websocket/BOSH for web clients)"
echo "7443       tcp    Openfire Web Binding HTTPS (websocket/BOSH for web clients)"
echo "7777       tcp    Openfire File Transfer Proxy (xmpp file transfers)"
if [ "$OPENFIRE_OPEN_ADMIN_PORTS" = "true" ]; then
echo "9090       tcp    Openfire Admin Console HTTP"
echo "9091       tcp    Openfire Admin Console HTTPS"
else
echo "9090/9091  tcp    Openfire Admin Console (closed on host firewall)"
fi
echo "8080       udp    TAK Server CoT/QUIC (ATAK 4.6+, optional)"
echo ""

echo "+++++++++++++++++++++++++++++++++++++++++++++++"
echo "+++++ OPENFIRE / TAK CHAT INSTALL COMPLETE ++++"
echo "+++++++++++++++++++++++++++++++++++++++++++++++"
