---
layout: page
title: TAKInstall Module
nav_title: TAKInstall
---

# TAKInstall Module

**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** `Posh-SSH`

## Purpose

TAKInstall provides cmdlets for remote provisioning of TAK Server 5.7 on a Rocky Linux 9 host over SSH. All operations run against an established `Posh-SSH` session — the target host is never required to have PowerShell installed.

## Prerequisites

- PowerShell 7.0 or later on the operator's workstation
- `Posh-SSH` module: `Install-Module Posh-SSH -Scope CurrentUser`
- An active SSH session to a Rocky Linux 9 host (the target must have `sudo` privileges)
- TAK Server 5.7-RELEASE8 RPM — obtained from tak.gov
- *(optional)* TAK Server GPG key for signature verification

## Installing

```powershell
Import-Module .\TAKInstall\TAKInstall.psd1
```

## Typical Workflow

```powershell
$sess = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential) -AcceptKey -Force
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

Install-TAKServer         -SshSession $sess -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' -Credential (Get-Credential)
New-TAKServerCertificate  -SshSession $sess -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' -KeystorePassword $pass
Set-TAKAdminCertificate   -SshSession $sess

# Optional add-ons
Install-TAKOpenfire               -SshSession $sess
New-TAKLetsEncryptCertificate     -SshSession $sess -DomainName 'tak.example.com' -KeystorePassword $pass -RenewalScriptPath '.\takserver_renewLECerts.sh'
```

## Cmdlet Reference

### `Install-TAKServer`

**Synopsis:** Installs TAK Server 5.7-RELEASE8 on a Rocky Linux 9 host via SSH.

**Steps performed:**
1. Raise open-files ulimit in `/etc/security/limits.conf`
2. Install `dnf-plugins-core`, `vim`, and `epel-release`
3. Add PostgreSQL PGDG repository; disable built-in `postgresql` module
4. Install OpenJDK 17; enable CRB repo; update system packages
5. Upload TAK Server RPM (and optional GPG key) via SCP
6. *(optional)* Verify RPM GPG signature
7. Install TAK Server RPM via `dnf`
8. Install `checkpolicy`; apply TAK SELinux policy; verify module
9. `systemctl enable --now takserver`; wait for service ready
10. Install `firewalld`; open ports 8089, 8443, 8446
11. Deploy certificate helper scripts to `/opt/tak/certs/`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session to the target host |
| `RpmPath` | String | Yes | Local path to `takserver-5.7-RELEASE8.noarch.rpm` |
| `Credential` | PSCredential | Yes | SSH credential for SCP file upload |
| `GpgKeyPath` | String | No | Local path to the TAK Server GPG signing key |
| `RemoteWorkDir` | String | No | Remote upload directory (default: `/tmp/tak_install`) |
| `SkipGpgVerification` | Switch | No | Skip GPG check even when `GpgKeyPath` is supplied |

**Examples:**

```powershell
# Basic install
Install-TAKServer -SshSession $sess -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' -Credential $cred

# With GPG verification and verbose output
Install-TAKServer -SshSession $sess `
    -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' `
    -GpgKeyPath '.\takserver-public-gpg.key' `
    -Credential $cred `
    -Verbose
```

---

### `New-TAKServerCertificate`

**Synopsis:** Creates the TAK Server CA, server certificate, and configures TAK Server for x509 client authentication.

**Steps performed:**
1. Remove existing cert files from `/opt/tak/certs/files`
2. Patch `cert-metadata.sh` with supplied org details
3. Create Root CA (`makeRootCa.sh`)
4. Create Intermediate (signing) CA
5. Create TAK Server certificate
6. Create admin client certificate
7. Create initial user client certificate
8. Restart `takserver`; wait for service ready
9. Patch `CoreConfig.xml`: enable x509 TLS input on port 8089
10. Patch `CoreConfig.xml`: switch to intermediate CA trust store
11. Patch `CoreConfig.xml`: insert certificate signing block (30-day validity)
12. Patch `CoreConfig.xml`: enable x509 group cache
13. Final `takserver` restart

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session |
| `State` | String | Yes | State/province — UPPERCASE, no spaces (e.g. `TX`) |
| `City` | String | Yes | City/locality — UPPERCASE, no spaces (e.g. `AUSTIN`) |
| `Organization` | String | Yes | Org name — UPPERCASE, no spaces (e.g. `MYORG`) |
| `OrganizationalUnit` | String | Yes | OU — UPPERCASE, no spaces (e.g. `OPS`) |
| `CAName` | String | No | Root CA identifier (default: `TAK-CA`) |
| `KeystorePassword` | SecureString | Yes | Password for JKS keystores and CoreConfig cert-signing block |
| `ServiceRestartTimeout` | Int | No | Seconds to wait for service after each restart (default: 300, max: 600) |

**Notes:**
- `State`, `City`, `Organization`, and `OrganizationalUnit` must be uppercase with no spaces — TAK Server enforces this.
- Certificate validity for enrolled user certs is 30 days (per TAK Server 5.7 Appendix C).

**Examples:**

```powershell
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

New-TAKServerCertificate -SshSession $sess `
    -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' `
    -KeystorePassword $pass

# Custom CA name with extended timeout
New-TAKServerCertificate -SshSession $sess `
    -State 'VA' -City 'RESTON' -Organization 'TAKACME' -OrganizationalUnit 'ADMIN' `
    -CAName 'ACME-TAKCA' -KeystorePassword $pass -ServiceRestartTimeout 600
```

---

### `Set-TAKAdminCertificate`

**Synopsis:** Promotes the TAK Server admin certificate to the administrator role.

**Steps performed:**
1. Wait for `takserver` service and admin API to be ready
2. Run `UserManager.jar certmod -A admin.pem` (retries on Ignite startup errors)
3. Restart `takserver`; wait for service ready
4. Copy `admin.p12` to `/home/atak/admin.p12` (permissions 640)

After this step, retrieve `/home/atak/admin.p12` and import it into your browser to access WebTAK as an administrator.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session |
| `ServiceRestartTimeout` | Int | No | Seconds to wait for service (default: 300) |

**Examples:**

```powershell
Set-TAKAdminCertificate -SshSession $sess

Set-TAKAdminCertificate -SshSession $sess -ServiceRestartTimeout 600 -Verbose
```

---

### `Install-TAKOpenfire`

**Synopsis:** Installs Openfire XMPP Server on a Rocky Linux 9 TAK Server host via SSH.

Must be run after `Install-TAKServer`.

**Steps performed:**
1. Disable Cockpit (frees port 9090)
2. Ensure Java 17 is installed
3. Download Openfire 5.0.3 RPM from GitHub
4. Repair `/etc/init.d` if it is a plain file rather than a directory
5. Install Openfire RPM via `dnf`
6. Create native `openfire-xmpp.service` systemd unit
7. Stop legacy init.d Openfire process
8. `systemctl enable --now openfire-xmpp.service`; wait for ready
9. Open firewall ports for XMPP and file transfer (5222, 5223, 5269, 7070, 7443, 7777, 8080)
10. *(optional)* Open admin console ports 9090/9091

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SshSession` | SSH.SshSession | *(required)* | Active Posh-SSH session |
| `OpenAdminPorts` | Bool | `$true` | Open Openfire admin console ports (9090/9091) in firewalld |
| `OpenFireVersion` | String | `5.0.3` | Openfire version to download (used to construct the GitHub URL) |

**Notes:**
- Cockpit (port 9090) is disabled — do not use this cmdlet if Cockpit is required.
- The Openfire RPM download has no hash verification (known limitation). For production use, verify the SHA256 manually against the Openfire release page.
- After the cmdlet completes, browse to `http://<server-ip>:9090` to complete the Openfire setup wizard.

**Examples:**

```powershell
# Default install with admin ports open
Install-TAKOpenfire -SshSession $sess

# Without exposing admin console; access via SSH tunnel instead:
#   ssh -L 9090:localhost:9090 user@server
Install-TAKOpenfire -SshSession $sess -OpenAdminPorts:$false
```

---

### `New-TAKLetsEncryptCertificate`

**Synopsis:** Issues a Let's Encrypt TLS certificate for a TAK Server host.

**Prerequisites:**
- Server has a public IP address
- A DNS A record for `-DomainName` points to the server's public IP
- Port 80 is reachable from the internet (ACME HTTP-01 challenge)

**Steps performed:**
1. Open firewall ports 8089, 8443, 8446, and 80
2. Install `snapd`; wait for seed
3. Install `certbot` via snap
4. `certbot certonly --standalone` for the domain
5. Export PEM → PKCS12 → JKS using `openssl` and `keytool`
6. Move JKS to `/opt/tak/certs/files/`
7. Stop `takserver`; patch 8446 connector in `CoreConfig.xml` to use LE JKS; start `takserver`
8. Write renewal config to `/etc/takserver_renew.conf` (permissions 600)
9. Upload and install `takserver_renewLECerts.sh` to `/etc/cron.monthly/`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session |
| `DomainName` | String | Yes | FQDN for the certificate (e.g. `tak.example.com`) |
| `KeystorePassword` | SecureString | Yes | Password for PKCS12/JKS keystores and renewal conf |
| `RenewalScriptPath` | String | Yes | Local path to `takserver_renewLECerts.sh` |

**Notes:**
- `/etc/takserver_renew.conf` stores the keystore password in plaintext (permissions 600, owned by root). For stricter environments, consider a secrets manager.

**Examples:**

```powershell
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'
New-TAKLetsEncryptCertificate -SshSession $sess `
    -DomainName 'tak.example.com' `
    -KeystorePassword $pass `
    -RenewalScriptPath '.\takserver_renewLECerts.sh'
```

---

### `Update-TAKLetsEncryptCertificate`

**Synopsis:** Renews the Let's Encrypt TLS certificate on a TAK Server host.

Run automatically by the cron job at `/etc/cron.monthly/takserver_renewLECerts.sh`. Use this cmdlet for manual renewal or to handle a domain name change.

**Steps performed:**
1. Load domain and password from parameters or from `/etc/takserver_renew.conf`
2. `certbot renew`
3. Export PEM → PKCS12 → JKS
4. Replace existing JKS/P12 files in `/opt/tak/certs/files/`
5. Restore `/opt/tak` ownership to the `tak` user
6. Stop and restart `takserver`

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session |
| `DomainName` | String | No | FQDN to renew; reads from conf if omitted |
| `KeystorePassword` | SecureString | No | Keystore password; reads from conf if omitted |
| `ServiceRestartTimeout` | Int | No | Seconds to wait for service restart (default: 180) |

**Examples:**

```powershell
# Renew using values from /etc/takserver_renew.conf
Update-TAKLetsEncryptCertificate -SshSession $sess

# Renew with explicit values
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'
Update-TAKLetsEncryptCertificate -SshSession $sess `
    -DomainName 'tak.example.com' `
    -KeystorePassword $pass
```

**Verifying renewal succeeded:**

After the cmdlet returns, confirm the new certificate is active on port 8446:

```powershell
# Check expiry via SSH
Invoke-SSHCommand -SessionId $sess.SessionId `
    -Command "sudo openssl x509 -enddate -noout -in /etc/letsencrypt/live/tak.example.com/cert.pem"

# Confirm the cert is loaded on port 8446
Invoke-SSHCommand -SessionId $sess.SessionId `
    -Command "echo | openssl s_client -connect localhost:8446 2>/dev/null | openssl x509 -noout -dates"
```

If port 8446 still shows the old expiry, TAK Server may not have restarted cleanly — check `ServiceRestartTimeout` or restart manually via SSH.

---

## Gaps and Known Issues

- `Install-TAKServer` requires `-Credential` for SCP uploads because Posh-SSH 3.x does not support session-based SCP. The credential must match the SSH session.
- `Install-TAKOpenfire` downloads the Openfire RPM with no hash verification. Verify manually against the Openfire release SHA256 before use in production.
- `New-TAKLetsEncryptCertificate` stores the keystore password in plaintext in `/etc/takserver_renew.conf` (permissions 600). Consider replacing this with a secrets manager for classified or production deployments.
- `New-TAKServerCertificate` uses `sed` to patch `CoreConfig.xml`. If the expected XML patterns are absent (e.g. due to a version change), the patch will silently fail; a validation step checks the signing block and throws a terminating error if missing.
