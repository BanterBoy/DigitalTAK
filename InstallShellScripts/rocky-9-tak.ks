#
# Rocky Linux 9 — Unattended Kickstart for Hyper-V Gen 2 TAK Server
# =================================================================
# This file is a PowerShell-processed template.  Before use, all
# %%PLACEHOLDER%% tokens must be replaced by the calling script:
#
#   %%USERNAME%%      - SSH/Linux admin username (e.g. atak)
#   %%USERPASSWORD%%  - Admin user's plaintext password
#   %%ROOTPASSWORD%%  - Root account plaintext password
#   %%HOSTNAME%%      - Hostname assigned during install (e.g. takserver)
#   %%TIMEZONE%%      - IANA timezone string (e.g. Europe/London)
#   %%KEYBOARD%%      - Keyboard variant (e.g. gb)
#   %%LANG%%          - Locale string (e.g. en_GB.UTF-8)
#   %%SSHPUBKEY%%     - Optional SSH public key line (empty string skips injection)
#
# Usage from PowerShell:
#   $ks = Get-Content .\InstallShellScripts\rocky-9-tak.ks -Raw
#   $ks = $ks -replace '%%USERNAME%%',      $username
#   $ks = $ks -replace '%%USERPASSWORD%%',  $userPw
#   $ks = $ks -replace '%%ROOTPASSWORD%%',  $rootPw
#   $ks = $ks -replace '%%HOSTNAME%%',      $hostname
#   $ks = $ks -replace '%%TIMEZONE%%',      $timezone
#   $ks = $ks -replace '%%KEYBOARD%%',      $keyboard
#   $ks = $ks -replace '%%LANG%%',          $lang
#   $ks = $ks -replace '%%SSHPUBKEY%%',     $sshPubKey   # or ''
# =================================================================

# ── Installer mode ────────────────────────────────────────────────────────────
text
cdrom

# ── Locale and keyboard ───────────────────────────────────────────────────────
lang %%LANG%%
keyboard --vckeymap=%%KEYBOARD%%

# ── Network ───────────────────────────────────────────────────────────────────
# DHCP on the first Hyper-V synthetic NIC; hostname set here and in %post.
network --bootproto=dhcp --device=eth0 --onboot=on --activate --hostname=%%HOSTNAME%%

# ── Accounts ──────────────────────────────────────────────────────────────────
rootpw --plaintext %%ROOTPASSWORD%%
user --name=%%USERNAME%% --plaintext --password=%%USERPASSWORD%% --groups=wheel

# ── Time ──────────────────────────────────────────────────────────────────────
timezone %%TIMEZONE%% --utc

# ── Boot loader ───────────────────────────────────────────────────────────────
bootloader --location=mbr --append="crashkernel=auto"

# ── Disk partitioning ─────────────────────────────────────────────────────────
# Wipe everything; use GPT + LVM on the first disk.
# Explicit layout provides reproducible sizing and avoids autopart surprises.
ignoredisk --only-use=sda
clearpart --all --initlabel --disklabel=gpt --drives=sda

part /boot/efi --fstype=efi  --size=600   --fsoptions="umask=0077"
part /boot     --fstype=xfs  --size=1024
part pv.01     --fstype=lvmpv --grow --size=1

volgroup takserver pv.01

# /         40 GiB — OS + TAK RPM + logs
logvol /    --fstype=xfs --vgname=takserver --name=root   --size=40960

# /var      20 GiB — PostgreSQL data, TAK logs, Openfire data
logvol /var --fstype=xfs --vgname=takserver --name=var    --size=20480

# swap      4 GiB — Java GC needs headroom
logvol swap --fstype=swap --vgname=takserver --name=swap  --size=4096

# Remaining space left unallocated — can be extended later with lvextend

# ── Security services ─────────────────────────────────────────────────────────
selinux --enforcing
firewall --enabled --service=ssh

# ── Installer behaviour ───────────────────────────────────────────────────────
firstboot --disable
reboot

# ── Package selection ─────────────────────────────────────────────────────────
%packages
@^minimal-environment

# SSH
openssh-server
openssh-clients

# Hyper-V integration (IP reporting, file-copy, shutdown)
hyperv-daemons

# Tools needed for TAK Server installation and administration
curl
wget
tar
unzip
sudo
vim-enhanced
net-tools
bind-utils
openssl

%end

# ── Post-installation ─────────────────────────────────────────────────────────
%post --log=/root/ks-post.log
#!/usr/bin/env bash
set -euo pipefail

# ── SSH daemon ──────────────────────────────────────────────────────────────
systemctl enable sshd

# Allow password authentication — required for initial Posh-SSH connection.
# After deployment is complete, operators can harden this setting.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# ── SSH public key injection ───────────────────────────────────────────────
# If %%SSHPUBKEY%% is non-empty, inject it for the admin user.
SSHPUBKEY="%%SSHPUBKEY%%"
if [ -n "${SSHPUBKEY}" ]; then
    SSH_DIR="/home/%%USERNAME%%/.ssh"
    mkdir -p "${SSH_DIR}"
    echo "${SSHPUBKEY}" >> "${SSH_DIR}/authorized_keys"
    chmod 700 "${SSH_DIR}"
    chmod 600 "${SSH_DIR}/authorized_keys"
    chown -R %%USERNAME%%:%%USERNAME%% "${SSH_DIR}"
    echo "[ks-post] SSH public key injected for %%USERNAME%%"
fi

# ── Sudo without password ──────────────────────────────────────────────────
# Deploy-CivTAK.ps1 uses passwordless sudo for remote commands.
cat > /etc/sudoers.d/%%USERNAME%% << 'SUDOEOF'
%%USERNAME%% ALL=(ALL) NOPASSWD: ALL
SUDOEOF
chmod 440 /etc/sudoers.d/%%USERNAME%%

# ── NetworkManager: ensure autoconnect at boot ─────────────────────────────
CONNECTION=$(nmcli -t -f NAME con show 2>/dev/null | head -1)
if [ -n "${CONNECTION}" ]; then
    nmcli con mod "${CONNECTION}" connection.autoconnect yes ipv4.method auto 2>/dev/null || true
fi
systemctl enable NetworkManager

# ── Hostname ──────────────────────────────────────────────────────────────
hostnamectl set-hostname %%HOSTNAME%%

# ── Disable IPv6 (optional — reduces noise in TAK network logs) ───────────
# Comment out the next two lines if IPv6 is required in your environment.
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-tak.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-tak.conf

# ── File descriptor limits for TAK Server (Java) ──────────────────────────
cat >> /etc/security/limits.conf << 'LIMITEOF'
*    soft nofile 32768
*    hard nofile 32768
LIMITEOF

# ── Hyper-V: ensure synthetic NIC comes up as eth0 ────────────────────────
# Modern kernels may name the NIC differently; create a udev rule for
# predictable naming based on the Hyper-V driver.
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/70-tak-net.rules << 'UDEVEOF'
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="hv_netvsc", NAME="eth0"
UDEVEOF

echo "[ks-post] Post-install configuration complete."
%end
