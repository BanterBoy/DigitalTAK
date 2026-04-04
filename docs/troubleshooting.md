---
layout: page
title: Troubleshooting
nav_title: Troubleshooting
---

{: .no_toc }

Diagnosis and resolution steps for common DigitalTAK deployment failures.
{: .fs-6 .fw-300 }

> *Chuck Norris doesn't troubleshoot. Problems quietly fix themselves before he notices.*

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## VM Boot Failures

### Symptom: VM does not appear in Hyper-V Manager after `New-TAKVirtualMachine`

**Cause:** PowerShell session is not elevated, or the Hyper-V feature is not enabled.

**Resolution:**
```powershell
# Verify Hyper-V is enabled
Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online

# If disabled, enable it (reboot required)
Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online

# Re-run in an elevated (Administrator) PowerShell session
Start-Process pwsh -Verb RunAs
```

---

### Symptom: VM boots but Rocky Linux installer does not start; UEFI shell appears instead

**Cause:** Secure Boot is rejecting the ISO, or the VHDX boot order is wrong.

**Resolution:**

1. Connect to the VM console: `vmconnect.exe $env:COMPUTERNAME TAKServer`
2. At the UEFI shell prompt, identify the Rocky Linux EFI binary:
   ```
   map -r
   fs0:
   ls EFI\BOOT\
   ```
3. Boot it manually: `fs0:\EFI\BOOT\BOOTX64.EFI`
4. Long-term: Disable Secure Boot on the VM in Hyper-V Manager → Settings → Security → uncheck "Enable Secure Boot".

---

### Symptom: Rocky Linux installer completes but the VM reboots back into the ISO

**Cause:** The ISO is still the first boot device.

**Resolution:**
In Hyper-V Manager → Settings → SCSI Controller, remove the DVD drive or move the hard disk above it in the boot order (Firmware tab). Then perform a normal restart.

---

### Symptom: `Deploy-TAKServer.ps1` fails at Phase 1 with "No External virtual switch found"

**Cause:** No External Hyper-V switch exists, and auto-creation failed (no active physical NIC).

**Resolution:**
```powershell
# List physical NICs
Get-NetAdapter | Where-Object Status -eq 'Up'

# Create an External switch using a specific NIC (brief network disruption expected)
New-VMSwitch -Name 'ExternalSwitch' -NetAdapterName 'Ethernet' -AllowManagementOS $true

# Re-run the deployment
$certPw = Read-Host -AsSecureString 'Certificate password'
.\Deploy-TAKServer.ps1 -SwitchName 'ExternalSwitch' -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
```

---

## SSH Timeout Failures

### Symptom: `Wait-TAKLinuxInstall` times out waiting for SSH

**Cause:** The Rocky Linux installation has not completed, the VM has no IP address, or firewalld is blocking SSH.

**Diagnosis steps:**

1. Open the VM console and check installer progress: `vmconnect.exe $env:COMPUTERNAME TAKServer`
2. After the OS has booted to a login prompt, get the VM's IP:
   ```powershell
   (Get-VMNetworkAdapter -VMName 'TAKServer').IPAddresses
   ```
3. Test SSH manually:
   ```powershell
   Test-NetConnection -ComputerName <IP> -Port 22
   ```

**Resolution:**
- If the IP is blank, Hyper-V Integration Services may not be running. Log in via console and run `sudo systemctl start hyperv-*` or manually set a static IP.
- If port 22 is unreachable, verify the guest firewall: `sudo firewall-cmd --list-all`.
- Extend the SSH timeout when re-running:
  ```powershell
  $certPw = Read-Host -AsSecureString 'Certificate password'
  .\Deploy-TAKServer.ps1 -SSHTimeoutSeconds 1800 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
  ```

---

### Symptom: SSH connects but `Invoke-TAKRemoteCommand` fails with "Permission denied"

**Cause:** The credential supplied does not have `sudo` access, or the account name is wrong.

**Resolution:**
```bash
# On the guest — verify sudo works
sudo id

# Add user to wheel group if missing
sudo usermod -aG wheel atak
```

---

### Symptom: `Install-TAKServer` fails at SCP upload — "Could not upload file"

**Cause:** `Posh-SSH` 3.x SCP requires a separate credential for the file transfer even when an SSH session already exists.

**Resolution:** Always pass `-Credential` explicitly to `Install-TAKServer`:
```powershell
Install-TAKServer -SshSession $sess `
    -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential $cred   # <-- required even with an active session
```

---

## Certificate Errors

### Symptom: `New-TAKServerCertificate` fails — "sed: can't find label for jump to 'end'"

**Cause:** The `CoreConfig.xml` on the server does not contain the expected XML patterns that `cert-metadata.sh` and `createTakCerts.sh` try to patch with `sed`.

**Diagnosis:**
```bash
# On the guest — check the file exists and is not empty
ls -lh /opt/tak/CoreConfig.xml
grep -c "certificateSigning" /opt/tak/CoreConfig.xml
```

**Resolution:**
- If the file is empty or missing, TAK Server did not finish starting. Check service status:
  ```bash
  sudo systemctl status takserver
  sudo journalctl -u takserver -n 50
  ```
- If `takserver` failed to start because PostgreSQL is not running:
  ```bash
  sudo systemctl start postgresql-16
  sudo systemctl start takserver
  ```
- After the service is healthy, re-run `New-TAKServerCertificate`.

---

### Symptom: `Set-TAKAdminCertificate` fails — "Ignite timeout" or "UserManager.jar returned non-zero"

**Cause:** TAK Server's Apache Ignite distributed cache has not finished initialising. This can take 2–5 minutes after a restart.

**Resolution:**
```powershell
# Increase the service restart timeout
Set-TAKAdminCertificate -SshSession $sess -ServiceRestartTimeout 600
```

On the guest, check Ignite startup progress:
```bash
sudo journalctl -u takserver -f | grep -i ignite
```
Wait until you see `Ignite node started OK` before re-running the cmdlet.

---

### Symptom: Certificate fields rejected — "Invalid value for STATE/CITY/ORG/OU"

**Cause:** TAK Server requires certificate subject fields to be **uppercase with no spaces**. Lowercase or space-containing values cause `makeRootCa.sh` to fail silently.

**Resolution:** Always pass uppercase, no-space values:
```powershell
# Correct
New-TAKServerCertificate -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' ...

# Wrong — will fail
New-TAKServerCertificate -State 'Texas' -City 'San Antonio' -Organization 'My Org' ...
```

---

### Symptom: Browser rejects `admin.p12` import — "Invalid password" or "File format not recognised"

**Cause:** The `.p12` file was copied with wrong permissions or is zero-length, or the keystore password is incorrect.

**Diagnosis:**
```bash
# On the guest — check file
ls -lh /home/atak/admin.p12
openssl pkcs12 -in /home/atak/admin.p12 -noout 2>&1
```

**Resolution:**
- Re-download the `.p12` from the server using SFTP:
  ```powershell
  $sftp = New-SFTPSession -ComputerName <IP> -Credential $cred -AcceptKey
  Get-SFTPItem -SessionId $sftp.SessionId -Path '/home/atak/admin.p12' -Destination '.\reports\certs\'
  ```
- Confirm the password is the same `KeystorePassword` passed to `New-TAKServerCertificate`.

---

### Symptom: ATAK client connects but shows "Certificate not trusted"

**Cause:** The client's trust anchor is not set to the TAK Server's intermediate CA.

**Resolution:**
1. Export the CA certificate from the server:
   ```bash
   scp atak@<IP>:/opt/tak/certs/files/ca.pem ./ca.pem
   ```
2. In ATAK → Settings → Network → TAK Servers → Add Server, import the CA `.pem` as the trust anchor.
3. Alternatively, use ATAK's Certificate Enrollment (port 8446) to receive a full certificate package.

---

## Port Unreachability

### Symptom: `Test-NetConnection -Port 8443` succeeds from the VM itself but fails from the Windows host

**Cause:** The Hyper-V vSwitch is Internal-only; traffic between the host management OS and the guest is not routed.

**Resolution:**
1. Confirm the switch type:
   ```powershell
   Get-VMSwitch | Select-Object Name, SwitchType
   ```
2. If `SwitchType = Internal`, either:
   - Convert to an External switch (requires a physical NIC and brief network disruption), or
   - Add a NAT network using `New-NetNat` to route host-to-guest traffic on the Internal switch.

---

### Symptom: Ports 8089/8443/8446 are unreachable after deploy

**Cause:** `firewalld` rules were not applied, or the TAK Server service is not running.

**Diagnosis on guest:**
```bash
# Check service
sudo systemctl status takserver

# Check firewall rules
sudo firewall-cmd --list-ports

# Expected output should include:
# 8089/tcp  8443/tcp  8446/tcp  22/tcp
```

**Resolution:**
```bash
# Re-apply firewall rules if missing
sudo firewall-cmd --permanent --add-port=8089/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=8446/tcp
sudo firewall-cmd --reload

# Restart TAK Server if stopped
sudo systemctl restart takserver
```

---

### Symptom: REST API calls fail with "Connection refused" on port 8443

**Cause:** TAK Server is running but the HTTPS connector has not started (common during cert reconfiguration).

**Diagnosis:**
```bash
sudo journalctl -u takserver -n 100 | grep -i "8443\|connector\|error"
```

Look for `CoreConfig.xml` parse errors or missing keystore file references. A misconfigured `certificateSigning` block will prevent the connector from binding.

---

## TAK Server Service Failures

### Symptom: `takserver` service fails to start — "Exit code 1"

**Cause:** PostgreSQL is not running, or the `CoreConfig.xml` contains a syntax error.

**Diagnosis:**
```bash
sudo systemctl status takserver
sudo journalctl -u takserver --no-pager | tail -50
sudo systemctl status postgresql-16
```

**Resolution:**
```bash
# Start PostgreSQL first
sudo systemctl start postgresql-16
sudo systemctl enable postgresql-16

# Then start TAK Server
sudo systemctl start takserver
```

---

### Symptom: TAK Server starts but REST API returns 503 / not responding

**Cause:** The Ignite distributed cache or the Tomcat web server has not finished initialising. Normal start time is 60–120 seconds; allow 3 minutes after a cold start.

**Resolution:**
```bash
# Watch logs until "Server is running and ready to serve"
sudo journalctl -u takserver -f | grep -E "ready|started|error|exception"
```

If the server never becomes ready, check for Java heap issues:
```bash
sudo journalctl -u takserver | grep "OutOfMemoryError"
```
Increase the VM memory allocation if heap exhaustion is seen (default is 8 GB; TAK Server recommends a minimum of 4 GB heap).

---

## Openfire / XMPP Issues

### Symptom: Openfire admin console (port 9090) is unreachable

**Cause:** Cockpit was not disabled, or the `openfire-xmpp.service` systemd unit was not created correctly.

**Diagnosis:**
```bash
# Check which process owns port 9090
sudo ss -tlnp | grep 9090

# Check Openfire service
sudo systemctl status openfire-xmpp.service
sudo journalctl -u openfire-xmpp.service -n 50
```

**Resolution:**
```bash
# Disable Cockpit to free port 9090
sudo systemctl disable --now cockpit.socket cockpit

# Restart Openfire
sudo systemctl restart openfire-xmpp.service
```

---

### Symptom: `Install-TAKOpenfire` fails at the RPM download step

**Cause:** The GitHub Releases URL for Openfire 5.0.3 may have changed, or there is no outbound internet access.

**Resolution:**
1. Download the Openfire RPM manually from the [Openfire GitHub releases page](https://github.com/igniterealtime/Openfire/releases/tag/v5.0.3).
2. Upload it to the guest via SCP:
   ```powershell
   Set-SFTPItem -SessionId $sftp.SessionId `
       -Path '.\openfire_5.0.3-1_all.rpm' `
       -Destination '/tmp/'
   ```
3. Install manually on the guest:
   ```bash
   sudo dnf install -y /tmp/openfire_5.0.3-1_all.rpm
   ```

---

### Symptom: ATAK clients cannot connect to Openfire (TAKChat)

**Cause:** Firewall rules for XMPP ports were not applied, or Openfire setup wizard was not completed.

**Diagnosis:**
```bash
sudo firewall-cmd --list-ports | grep 5222
```

**Resolution:**
```bash
# Apply XMPP firewall rules
sudo firewall-cmd --permanent --add-port=5222/tcp
sudo firewall-cmd --permanent --add-port=5223/tcp
sudo firewall-cmd --reload
```

Complete the Openfire setup wizard at `http://<server-ip>:9090` before connecting ATAK clients.

---

## Let's Encrypt Issues

### Symptom: `certbot certonly` fails — "Connection timed out during ACME challenge"

**Cause:** Port 80 is not reachable from the internet, or the DNS A record does not resolve to the server's public IP.

**Diagnosis:**
```bash
# On the guest — verify port 80 is open
sudo firewall-cmd --list-ports | grep "80"

# Verify public DNS resolution from the guest
dig +short <your-domain>
curl -s http://<your-domain>/.well-known/acme-challenge/test
```

**Resolution:**
```bash
# Open port 80 if missing
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```
Check with your DNS provider or cloud platform that the A record is correctly set to the server's public IP.

---

### Symptom: Let's Encrypt certificate renewal fails (monthly cron)

**Cause:** The domain no longer resolves to the server, or port 80 is blocked.

**Diagnosis:**
```bash
# Check renewal configuration
cat /etc/takserver_renew.conf

# Test renewal in dry-run mode
sudo certbot renew --dry-run
```

**Resolution:**
- Verify port 80 is still open: `sudo firewall-cmd --list-ports`
- If the server IP has changed, update the DNS A record before running renewal.
- To force an immediate renewal:
  ```bash
  sudo /etc/cron.monthly/takserver_renewLECerts.sh
  ```

---

## PowerShell Module Issues

### Symptom: `Import-Module .\TAKDeploy\TAKDeploy.psd1` fails — "Module not found" or "Could not load file"

**Cause:** PowerShell execution policy is blocking the module, or the path is wrong.

**Resolution:**
```powershell
# Check execution policy
Get-ExecutionPolicy

# If restricted, set for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Confirm you are in the repo root
Get-Location   # Should show C:\...\DigitalTAK
Import-Module .\TAKDeploy\TAKDeploy.psd1 -Force
```

---

### Symptom: `Connect-TAKServer` fails — "SSL/TLS connection error" or "authentication failed"

**Cause:** Server uses a self-signed certificate and `-SkipCertificateCheck` is `$false`, or the PFX path/password is wrong.

**Resolution:**
```powershell
# For self-signed certificates (default for new deployments):
Connect-TAKServer -HostName <IP> -PfxPath '.\admin.p12' -PfxPassword $pass -SkipCertificateCheck $true

# Verify the PFX is readable
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('admin.p12', $pass)
$cert.Subject   # Should show the admin cert DN
```

---

### Symptom: TAKServerPS cmdlets return "No active TAK Server session"

**Cause:** `Connect-TAKServer` was not called, or the session was lost due to a module reload.

**Resolution:**
```powershell
# Always connect before using any cmdlet
Connect-TAKServer -HostName <IP> -PfxPath '.\admin.p12' -PfxPassword $pass -SkipCertificateCheck $true

# Confirm a session exists
Get-TAKVersion   # Should return the server version string
```

---

## Deployment Resume / Snapshot Issues

### Symptom: Re-running `Deploy-TAKServer.ps1` does not resume from the last checkpoint

**Cause:** The expected snapshot names (`Phase0-RockyInstalled`, `Phase2-TAKInstalled`, `Phase4-CertsAndAdmin`) are missing, renamed, or the wrong VM name is being used.

**Diagnosis:**
```powershell
# List all snapshots for the VM
Get-VMSnapshot -VMName 'TAKServer' | Select-Object Name, CreationTime
```

**Resolution:**
- If the snapshot names differ from the expected values, you can rename them in Hyper-V Manager, or use `-DisableSnapshotResume` to force a fresh run from Phase 0.
- If the VM was renamed, pass the `-VMName` parameter explicitly:
  ```powershell
  $certPw = Read-Host -AsSecureString 'Certificate password'
  .\Deploy-TAKServer.ps1 -VMName 'TAKServer-Prod' -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
  ```

---

### Symptom: Phase rollback leaves the VM in a corrupt state

**Cause:** Rolling back while the VM is running can corrupt the VHDX.

**Resolution:** Always shut down the VM cleanly before rolling back:
```powershell
Stop-VM -Name 'TAKServer' -Force
.\Invoke-TAKRollback.ps1 -VMName 'TAKServer' -SnapshotName 'Phase2-TAKInstalled'
Start-VM -Name 'TAKServer'
```

---

## Collecting Diagnostic Information

When opening a support issue, include the following:

```powershell
# PowerShell and module versions
$PSVersionTable
(Get-Module TAKDeploy).Version
(Get-Module TAKInstall).Version
(Get-Module TAKServerPS).Version

# Hyper-V VM state
Get-VM -Name 'TAKServer' | Select-Object Name, State, MemoryAssigned, ProcessorCount
Get-VMSnapshot -VMName 'TAKServer' | Select-Object Name, CreationTime
```

On the guest (via SSH):
```bash
sudo systemctl status takserver postgresql-16
sudo journalctl -u takserver --no-pager | tail -100
sudo firewall-cmd --list-all
uname -r && cat /etc/rocky-release
java -version 2>&1
```
