---
layout: page
title: API Reference
nav_title: API Reference
---

# PowerShell API Reference
{: .no_toc }

Complete cmdlet reference for all three DigitalTAK PowerShell modules.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Module Overview

| Module | Manifest | Cmdlets | Purpose |
|--------|----------|---------|---------|
| **TAKDeploy** | `TAKDeploy\TAKDeploy.psd1` | 3 | Hyper-V VM orchestration |
| **TAKInstall** | `TAKInstall\TAKInstall.psd1` | 6 | Remote SSH provisioning over Posh-SSH |
| **TAKServerPS** | `TAKServerPS\TAKServer.psd1` | 44 | TAK Server 5.x REST API wrapper |

All modules require **PowerShell 7.0+**. All passwords must be passed as `SecureString`.

---

## TAKDeploy Module

Provides high-level orchestration for creating Hyper-V Gen 2 VMs and driving the end-to-end deployment pipeline.

**Import:**
```powershell
Import-Module .\TAKDeploy\TAKDeploy.psm1
```

**Prerequisites:** Elevated (Administrator) PowerShell session · Hyper-V enabled · `Posh-SSH` module

---

### `Start-TAKDeployment`

**Synopsis:** Interactive end-to-end orchestrator — deploys a full CivTAK instance from scratch on Hyper-V.

Drives the full deployment pipeline in phases. Hyper-V snapshots are taken after key phases so the run can be resumed after failure.

| Phase | Description |
|-------|-------------|
| 0 | Collect configuration interactively; check prerequisites |
| 1 | Create Hyper-V Gen 2 VM and boot Rocky Linux ISO |
| 1b | Wait for OS install to complete; establish SSH |
| 2a | `Install-TAKServer` — RPM, Java, SELinux, firewall |
| 2b | `New-TAKServerCertificate` — CA chain and server cert |
| 2c | `Set-TAKAdminCertificate` — promote admin cert |
| 2d | *(optional)* `Install-TAKOpenfire` |
| 2e | *(optional)* `New-TAKLetsEncryptCertificate` |
| 3 | Print deployment summary with access URLs |

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SkipVMCreation` | Switch | Off | Skip Phase 1/1b; prompts for an existing VM's IP and SSH credentials |

**Examples:**
```powershell
# Full interactive deployment
Start-TAKDeployment

# Skip VM creation — use an existing Rocky Linux VM
Start-TAKDeployment -SkipVMCreation
```

---

### `New-TAKVirtualMachine`

**Synopsis:** Creates a Hyper-V Gen 2 virtual machine configured for Rocky Linux 9.

Creates the VM and boots from the supplied ISO. Open the Hyper-V console to complete the OS install, then call `Wait-TAKLinuxInstall`.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `TAKServer` | Name of the VM in Hyper-V Manager |
| `VMPath` | String | `C:\Hyper-V\VMs` | Directory for VM configuration and VHDX |
| `IsoPath` | String | `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso` | Path to Rocky Linux 9 DVD ISO |
| `VHDSizeGB` | Int | `80` | Dynamic VHDX size in GB (min 20 · max 2048) |
| `MemoryStartupBytes` | Long | `8 GB` | Fixed memory allocation (dynamic memory disabled) |
| `ProcessorCount` | Int | `4` | Number of virtual processors (max 64) |
| `SwitchName` | String | *(auto-detect)* | Hyper-V External virtual switch name |

**Outputs:** `Microsoft.HyperV.PowerShell.VirtualMachine`

**Notes:**
- Requires an elevated PowerShell session.
- If no External vSwitch exists, offers to create one using the first active physical NIC. Network connectivity will briefly drop during switch creation.
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = High`).

**Examples:**
```powershell
# All defaults
New-TAKVirtualMachine

# Custom sizing
New-TAKVirtualMachine -VMName 'TAK-Lab' -VHDSizeGB 120 -ProcessorCount 8

# Connect to console to install Rocky Linux
vmconnect.exe $env:COMPUTERNAME TAKServer
```

---

### `Wait-TAKLinuxInstall`

**Synopsis:** Waits for the Rocky Linux installation to complete and establishes an SSH session.

Pauses for the operator to complete the OS install, then auto-detects the VM's IP and retries SSH until success or timeout.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `TAKServer` | Name of the Hyper-V VM |
| `TimeoutSeconds` | Int | `300` | Maximum seconds to attempt SSH (30–3600) |
| `RetryIntervalSeconds` | Int | `10` | Seconds between SSH attempts (5–120) |
| `Credential` | PSCredential | *(prompted)* | SSH credentials |

**Outputs:** `SSH.SshSession`

**Examples:**
```powershell
$session = Wait-TAKLinuxInstall -VMName 'TAKServer'
Install-TAKServer -SshSession $session -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' -Credential $cred

$session = Wait-TAKLinuxInstall -VMName 'TAK-Lab' -TimeoutSeconds 600
```

---

## TAKInstall Module

Provides cmdlets for remote provisioning of TAK Server 5.7 on a Rocky Linux 9 host over an SSH session established with `Posh-SSH`.

**Import:**
```powershell
Install-Module Posh-SSH -Scope CurrentUser
Import-Module .\TAKInstall\TAKInstall.psm1
```

**Prerequisites:** Active `Posh-SSH` SSH session · Target host with `sudo` access · TAK Server 5.7-RELEASE8 RPM

**Typical workflow:**
```powershell
$sess = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential) -AcceptKey -Force
$pass = Read-Host -AsSecureString 'Keystore password'

Install-TAKServer         -SshSession $sess -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' -Credential (Get-Credential)
New-TAKServerCertificate  -SshSession $sess -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' -KeystorePassword $pass
Set-TAKAdminCertificate   -SshSession $sess
```

---

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
| `SshSession` | SSH.SshSession | Yes | Active Posh-SSH session |
| `RpmPath` | String | Yes | Local path to `takserver-5.7-RELEASE8.noarch.rpm` |
| `Credential` | PSCredential | Yes | SSH credential for SCP upload (required by Posh-SSH 3.x) |
| `GpgKeyPath` | String | No | Local path to TAK Server GPG signing key |
| `RemoteWorkDir` | String | No | Remote upload directory (default: `/tmp/tak_install`) |
| `SkipGpgVerification` | Switch | No | Skip GPG check even when `GpgKeyPath` is supplied |

**Examples:**
```powershell
# Basic install
Install-TAKServer -SshSession $sess -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' -Credential $cred

# With GPG verification
Install-TAKServer -SshSession $sess `
    -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' `
    -GpgKeyPath '.\takserver-public-gpg.key' `
    -Credential $cred -Verbose
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
9. Patch `CoreConfig.xml` — enable x509 TLS input on port 8089
10. Patch `CoreConfig.xml` — switch to intermediate CA trust store
11. Patch `CoreConfig.xml` — insert certificate signing block (30-day validity)
12. Patch `CoreConfig.xml` — enable x509 group cache
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
| `KeystorePassword` | SecureString | Yes | Password for JKS keystores and `CoreConfig.xml` cert-signing block |
| `ServiceRestartTimeout` | Int | No | Seconds to wait for service after each restart (default: 300 · max: 600) |

**Notes:**
- `State`, `City`, `Organization`, and `OrganizationalUnit` must be uppercase with no spaces.
- Certificate enrollment validity is 30 days (hardcoded per TAK Server 5.7 Appendix C).

**Examples:**
```powershell
$pass = Read-Host -AsSecureString 'Keystore password'

New-TAKServerCertificate -SshSession $sess `
    -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' `
    -KeystorePassword $pass

# Custom CA name, extended timeout
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

After this step, retrieve `/home/atak/admin.p12` via SFTP and import it into your browser or ATAK client.

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
3. Download Openfire 5.0.3 RPM from GitHub Releases
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
| `OpenFireVersion` | String | `5.0.3` | Openfire version to download |

**Notes:**
- Cockpit (port 9090) is permanently disabled by this cmdlet.
- The Openfire RPM download has no hash verification. For production, verify the SHA256 against the Openfire release page.
- After the cmdlet completes, browse to `http://<server-ip>:9090` to complete the Openfire setup wizard.

**Examples:**
```powershell
# Default install with admin ports open
Install-TAKOpenfire -SshSession $sess

# Secure: close admin console; access via SSH tunnel
Install-TAKOpenfire -SshSession $sess -OpenAdminPorts:$false
# ssh -L 9090:localhost:9090 user@server
```

---

### `New-TAKLetsEncryptCertificate`

**Synopsis:** Issues a Let's Encrypt TLS certificate for a TAK Server host.

**Prerequisites:**
- Server has a public IP address
- DNS A record for `-DomainName` points to the server's public IP
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
$pass = Read-Host -AsSecureString 'Keystore password'
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
| `DomainName` | String | No | FQDN to renew; reads from `/etc/takserver_renew.conf` if omitted |
| `KeystorePassword` | SecureString | No | Keystore password; reads from conf if omitted |
| `ServiceRestartTimeout` | Int | No | Seconds to wait for service restart (default: 180) |

**Examples:**
```powershell
# Use values from /etc/takserver_renew.conf
Update-TAKLetsEncryptCertificate -SshSession $sess

# Explicit values
$pass = Read-Host -AsSecureString 'Keystore password'
Update-TAKLetsEncryptCertificate -SshSession $sess -DomainName 'tak.example.com' -KeystorePassword $pass
```

---

## TAKServerPS Module

REST API wrapper for TAK Server 5.x. All 44 cmdlets share a module-scoped session established with `Connect-TAKServer`.

**Import:**
```powershell
Import-Module .\TAKServerPS\TAKServer.psm1
```

**Prerequisites:** Running TAK Server instance · Admin `.p12` certificate (recommended) or username/password

---

### Session Management

#### `Connect-TAKServer`

Establishes a module-scoped session. Must be called before any other TAKServerPS cmdlet.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `HostName` | String | Yes | Hostname or IP of the TAK Server |
| `Port` | Int | No | HTTPS port (default: 8443) |
| `Certificate` | X509Certificate2 | No | Client certificate object *(Certificate set)* |
| `PfxPath` | String | No | Path to `.pfx`/`.p12` file *(Pfx set)* |
| `PfxPassword` | SecureString | No | Password for the PFX file |
| `Credential` | PSCredential | No | Basic auth credential *(Credential set)* |
| `Token` | SecureString | No | Pre-obtained Bearer token *(Token set)* |
| `SkipCertificateCheck` | Bool | No | Skip server cert validation (default: `$true`) |

**Outputs:** `PSCustomObject` (the active session object)

```powershell
# PFX file (recommended for production)
Connect-TAKServer -HostName tak.example.com -PfxPath '.\admin.p12' -PfxPassword $pass

# Certificate object
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('admin.p12', $pass)
Connect-TAKServer -HostName tak.example.com -Certificate $cert

# Basic auth
Connect-TAKServer -HostName tak.example.com -Credential (Get-Credential)

# Trusted certificate (Let's Encrypt)
Connect-TAKServer -HostName tak.example.com -PfxPath '.\admin.p12' -PfxPassword $pass -SkipCertificateCheck $false
```

#### `Disconnect-TAKServer`

Calls `/logout` and clears the module-scoped session.

| Parameter | Type | Description |
|-----------|------|-------------|
| `Force` | Switch | Clear local session without calling the remote logout endpoint |

---

### Server Info

#### `Get-TAKVersion`

Returns the TAK Server version string.

| Parameter | Type | Description |
|-----------|------|-------------|
| `Detailed` | Switch | Return full VersionInfo object (build date, git commit) |

```powershell
Get-TAKVersion           # "5.7-RELEASE-8"
Get-TAKVersion -Detailed # Full build info object
```

---

### Users

#### `Get-TAKUser`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns all currently connected users |
| `AccountList` | Switch | Returns all provisioned file-managed user accounts |
| `GroupName` | String | Filter accounts by group name (requires `-AccountList`) |
| `ConnectionId` | String | Returns the user record for a specific connection UID |

```powershell
Get-TAKUser                                         # Connected users
Get-TAKUser -AccountList                            # All accounts
Get-TAKUser -AccountList -GroupName 'Operators'     # Accounts in group
Get-TAKUser -ConnectionId 'ANDROID-abc'             # Specific connection
```

#### `New-TAKUser`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Credential` | PSCredential | Yes | Username and password for the new account |
| `GroupList` | String[] | No | Bi-directional group memberships |
| `InboundGroups` | String[] | No | Inbound-only group memberships |
| `OutboundGroups` | String[] | No | Outbound-only group memberships |

```powershell
$cred = Get-Credential -UserName 'fielduser1'
New-TAKUser -Credential $cred -GroupList 'Operators'
New-TAKUser -Credential $cred -InboundGroups 'Intel' -OutboundGroups 'Command'
```

#### `Remove-TAKUser`

| Parameter | Type | Description |
|-----------|------|-------------|
| `UserName` | String | Username to delete (pipeline-compatible) |
| `AlsoRevokeCertificates` | Switch | Revoke all certs for the user before deleting |

```powershell
Remove-TAKUser -UserName 'exuser1'
Remove-TAKUser -UserName 'exuser1' -AlsoRevokeCertificates
Get-TAKUser -AccountList | Where-Object { $_.username -like 'temp_*' } | Remove-TAKUser
```

#### `Set-TAKUserPassword`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Credential` | PSCredential | Yes | Username and new password |

```powershell
Set-TAKUserPassword -Credential (Get-Credential -UserName 'fielduser1')
```

---

### Groups

#### `Get-TAKGroup`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns all groups visible to the current user |
| `Name` | String | Specific group by name |
| `Direction` | `IN`\|`OUT` | Filter by direction (used with `-Name`) |
| `All` | Switch | Returns all groups including hidden (admin only) |

```powershell
Get-TAKGroup
Get-TAKGroup -All
Get-TAKGroup -Name 'Operators' -Direction IN
```

#### `Set-TAKUserGroup`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `UserName` | String | Yes | Username to update |
| `GroupList` | String[] | No | Bi-directional memberships |
| `InboundGroups` | String[] | No | Inbound-only memberships |
| `OutboundGroups` | String[] | No | Outbound-only memberships |

```powershell
Set-TAKUserGroup -UserName 'fielduser1' -GroupList 'Operators', 'Command'
Set-TAKUserGroup -UserName 'sensor1' -InboundGroups 'Intel' -OutboundGroups 'FieldTeam'
```

---

### Subscriptions

#### `Get-TAKSubscription`

```powershell
Get-TAKSubscription                     # All active subscriptions
Get-TAKSubscription -Uid 'ANDROID-abc'  # Specific subscription by UID
```

#### `Remove-TAKSubscription`

```powershell
Remove-TAKSubscription -Uid 'ANDROID-abc'
Get-TAKSubscription | Where-Object callsign -like 'OLD-*' | Remove-TAKSubscription -Confirm:$false
```

---

### Contacts and CoT

#### `Get-TAKContact`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SortBy` | `CALLSIGN`\|`UID` | `CALLSIGN` | Sort field |
| `Direction` | `ASCENDING`\|`DESCENDING` | `ASCENDING` | Sort direction |
| `NoFederates` | Switch | | Exclude federated contacts |
| `Full` | Switch | | Return full contact records including group mapping |

```powershell
Get-TAKContact
Get-TAKContact -SortBy UID -NoFederates
Get-TAKContact -Full
```

#### `Get-TAKCoT`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns current SA track for all contacts |
| `Uid` | String | Returns CoT XML for a specific UID |

```powershell
Get-TAKCoT
Get-TAKCoT -Uid 'ANDROID-abc123'
```

---

### Certificates

#### `Get-TAKCertificate`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All certificates |
| `UserName` | String | Filter by username |
| `Active` | Switch | Active certs only |
| `Revoked` | Switch | Revoked certs only |
| `Expired` | Switch | Expired certs only |

```powershell
Get-TAKCertificate
Get-TAKCertificate -UserName 'fielduser1'
Get-TAKCertificate -Expired
```

#### `Invoke-TAKCertificateSign`

Signs a PEM-encoded CSR using the TAK Server CA.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `CsrPem` | String | Yes | PEM-encoded CSR string (pipeline-compatible) |
| `Version2` | Switch | No | Use the `/v2` signing endpoint |

```powershell
$csr = Get-Content 'client.csr' -Raw
Invoke-TAKCertificateSign -CsrPem $csr
```

#### `Remove-TAKCertificate`

Revokes a certificate by its SHA-256 fingerprint.

| Parameter | Type | Description |
|-----------|------|-------------|
| `Hash` | String | Certificate SHA-256 hash (pipeline-compatible by value or `hash` property) |

```powershell
Remove-TAKCertificate -Hash 'abc123...'
Get-TAKCertificate -Expired | Remove-TAKCertificate
```

---

### Missions

#### `Get-TAKMission`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All missions |
| `Name` | String | Single mission by name |
| `Guid` | String | Single mission by GUID |
| `Tool` | String | Filter list by tool type (e.g. `public`, `vbm`) |
| `PasswordProtected` | Switch | Filter to password-protected missions |
| `IncludeChanges` | Switch | Include change log (single-mission mode) |
| `IncludeLogs` | Switch | Include log entries (single-mission mode) |
| `SecAgo` | Long | Content changed within last N seconds |
| `Start` / `End` | DateTime | Date range filter |

```powershell
Get-TAKMission
Get-TAKMission -Name 'OpBlue'
Get-TAKMission -Tool 'public' -IncludeChanges
```

#### `New-TAKMission`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique mission name |
| `Description` | String | No | Human-readable description |
| `Group` | String[] | No | Groups to assign (default: `__ANON__`) |
| `Tool` | String | No | Tool type (default: `public`) |
| `ChatRoom` | String | No | Associated chat room |
| `BaseLayer` | String | No | Base map layer name |
| `Bbox` | String | No | Bounding box (`minLon,minLat,maxLon,maxLat`) |
| `Classification` | String | No | Classification label |
| `Password` | SecureString | No | Access password |
| `DefaultRole` | String | No | `MISSION_OWNER`, `MISSION_SUBSCRIBER`, `MISSION_READONLY_SUBSCRIBER` |
| `InviteOnly` | Switch | No | Restrict to invited members |
| `Expiration` | Long | No | Unix timestamp expiry; `-1` for none (default) |

```powershell
New-TAKMission -Name 'OpBlue' -Description 'Blue force tracking' -Group 'TeamAlpha'
New-TAKMission -Name 'IntelBrief' -Tool 'vbm' -InviteOnly -DefaultRole MISSION_READONLY_SUBSCRIBER
```

#### `Remove-TAKMission`

```powershell
Remove-TAKMission -Name 'OpBlue'
Get-TAKMission -Tool 'test' | Remove-TAKMission
```

#### `Get-TAKMissionChange`

| Parameter | Type | Description |
|-----------|------|-------------|
| `Name` | String | Mission name (required) |
| `SecAgo` | Long | Changes in the last N seconds |
| `Start` / `End` | DateTime | Date range filter |

#### `Get-TAKMissionContact`

Returns contacts associated with a mission.

```powershell
Get-TAKMissionContact -Name 'OpBlue'
```

#### `Get-TAKMissionSubscription`

Returns active subscriptions for a mission.

```powershell
Get-TAKMissionSubscription -Name 'OpBlue'
```

#### `Register-TAKMissionSubscription`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `MissionName` | String | Yes | Mission to subscribe to |
| `Uid` | String | Yes | TAK client UID |
| `Role` | String | No | `MISSION_OWNER`, `MISSION_SUBSCRIBER` (default), `MISSION_READONLY_SUBSCRIBER` |

```powershell
Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'
Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123' -Role MISSION_OWNER
```

#### `Unregister-TAKMissionSubscription`

```powershell
Unregister-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'
```

---

### Network Inputs

#### `Get-TAKInput`

```powershell
Get-TAKInput               # All inputs
Get-TAKInput -Name 'UDP1'  # By name
```

#### `New-TAKInput`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique input name |
| `Protocol` | String | Yes | `tcp`, `udp`, `stcp`, `tcp_ssl`, `udp_broadcast` |
| `Port` | Int | Yes | Port to listen on (1–65535) |
| `Group` | String[] | No | Groups this input feeds |
| `Interface` | String | No | Bind address (default: `0.0.0.0`) |
| `Archive` | Switch | No | Archive received events |
| `AnonGroup` | Switch | No | Allow anonymous clients |
| `ArchiveOnly` | Switch | No | Store only, do not forward |
| `FederateOnly` | Switch | No | Forward to federates only |
| `AuthRequired` | Switch | No | Require client authentication |

```powershell
New-TAKInput -Name 'SACast' -Protocol udp -Port 4242
New-TAKInput -Name 'TLSClients' -Protocol tcp_ssl -Port 8089 -AuthRequired -Archive
```

#### `Remove-TAKInput`

```powershell
Remove-TAKInput -Name 'SACast'
Get-TAKInput | Where-Object port -gt 9000 | Remove-TAKInput -Confirm:$false
```

---

### Data Feeds

#### `Get-TAKDataFeed`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All data feed configurations |
| `Name` | String | Single feed by name |
| `Uuid` | String | Single feed by UUID (returns stats) |
| `Stats` | Switch | Stats for all feeds |

#### `New-TAKDataFeed`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique feed name |
| `Protocol` | String | Yes | `tcp`, `udp`, `stcp`, `tcp_ssl`, `udp_broadcast` |
| `Port` | Int | Yes | Port (1–65535) |
| `Group` | String[] | No | Groups this feed delivers to |
| `Interface` | String | No | Bind address (default: `0.0.0.0`) |
| `Archive` | Switch | No | Archive events |
| `AnonGroup` | Switch | No | Allow anonymous clients |
| `Type` | String | No | Feed type (e.g. `Full`, `Diff`) |
| `Tag` | String | No | Tag string |
| `Sync` | Switch | No | Enable data sync |

```powershell
New-TAKDataFeed -Name 'SensorFeed' -Protocol udp -Port 6666 -Group 'Operators'
New-TAKDataFeed -Name 'TLSFeed' -Protocol tcp_ssl -Port 8089 -Group '__ANON__' -Archive
```

#### `Remove-TAKDataFeed`

```powershell
Remove-TAKDataFeed -Name 'SensorFeed'
Get-TAKDataFeed | Where-Object protocol -eq 'udp' | Remove-TAKDataFeed -Confirm:$false
```

---

### Video Connections

#### `Get-TAKVideo`

```powershell
Get-TAKVideo
Get-TAKVideo | Where-Object active -eq $true
```

#### `New-TAKVideo`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Alias` | String | Yes | Friendly display name |
| `Feeds` | Object[] | Yes | Feed objects with at least a `url` property |
| `Uuid` | String | No | UUID (auto-generated if omitted) |
| `Active` | Bool | No | Visible to clients (default: `$true`) |
| `Thumbnail` | String | No | Thumbnail URL |
| `Classification` | String | No | Classification marking (e.g. `U//FOUO`) |

```powershell
$feed = @{ url = 'rtsp://10.0.0.50:8554/live'; type = 'rtsp' }
New-TAKVideo -Alias 'Drone Camera 1' -Feeds $feed
```

#### `Remove-TAKVideo`

```powershell
Remove-TAKVideo -Uid '7b3c9a2e-...'
Get-TAKVideo | Where-Object active -eq $false | Select-Object -ExpandProperty uuid | Remove-TAKVideo
```

---

### Outgoing Connections

#### `Get-TAKOutgoingConnection`

```powershell
Get-TAKOutgoingConnection
Get-TAKOutgoingConnection | Where-Object enabled -eq $true
```

#### `New-TAKOutgoingConnection`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Address` | String | Yes | Remote hostname or IP |
| `Port` | Int | Yes | Remote TCP port (1–65535) |
| `DisplayName` | String | Yes | Friendly name |
| `Tls` | Switch | No | Use TLS |
| `ProtocolVersion` | Int | No | Protocol version (default: 1) |
| `ReconnectInterval` | Int | No | Seconds between reconnects (default: 10) |
| `MaxRetries` | Int | No | Max reconnect attempts |
| `UnlimitedRetries` | Switch | No | Retry indefinitely |
| `Enabled` | Bool | No | Active immediately (default: `$true`) |
| `ConnectionToken` | String | No | Token for the connect handshake |
| `UseToken` | Switch | No | Include token in handshake |

```powershell
New-TAKOutgoingConnection -Address 'tak.example.com' -Port 8089 -Tls -DisplayName 'HQ Server'
New-TAKOutgoingConnection -Address '10.0.0.5' -Port 8087 -DisplayName 'Field Hub' -UnlimitedRetries
```

#### `Remove-TAKOutgoingConnection`

```powershell
Remove-TAKOutgoingConnection -Name 'HQ Server'
Get-TAKOutgoingConnection | Where-Object enabled -eq $false | Select-Object -ExpandProperty displayName | Remove-TAKOutgoingConnection
```

---

### Federation

#### `Get-TAKFederate`

```powershell
Get-TAKFederate
Get-TAKFederate | Where-Object enabled -eq $true
```

{: .note }
`New-TAKFederate` and `Remove-TAKFederate` are not implemented. Federation configuration must be performed via WebTAK or direct REST API.

---

### Security Configuration

#### `Get-TAKSecurityConfig`

Returns TLS settings, cipher suites, and authentication policy.

```powershell
Get-TAKSecurityConfig
```

#### `Set-TAKSecurityConfig`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Config` | Object | Yes | Security config object (from `Get-TAKSecurityConfig`) |

```powershell
$cfg = Get-TAKSecurityConfig
$cfg.auth = 'ldap'
Set-TAKSecurityConfig -Config $cfg
```

#### `Remove-TAKToken`

| Parameter | Type | Description |
|-----------|------|-------------|
| `Token` | String | Single token to revoke |
| `Tokens` | String[] | Multiple tokens for bulk revocation |

```powershell
Remove-TAKToken -Token 'eyJhbGci...'
Remove-TAKToken -Tokens 'token1', 'token2', 'token3'
```

---

### Plugins

#### `Get-TAKPlugin`

Returns metadata for all installed TAK Server plugins.

```powershell
Get-TAKPlugin
```

---

### Map Layers

#### `Get-TAKMapLayer`

```powershell
Get-TAKMapLayer
Get-TAKMapLayer -Uid '7b3c9a2e-...'
```

#### `Remove-TAKMapLayer`

```powershell
Remove-TAKMapLayer -Uid '7b3c9a2e-...'
Get-TAKMapLayer | Where-Object name -like 'TEMP_*' | Remove-TAKMapLayer -Confirm:$false
```

---

### Device Profiles

#### `Get-TAKDeviceProfile`

Returns the device enrollment/provisioning profile (settings pushed to enrolled TAK clients on connection).

```powershell
Get-TAKDeviceProfile
```

---

## Cmdlet Quick Reference

### TAKDeploy (3 cmdlets)

| Cmdlet | Purpose |
|--------|---------|
| `Start-TAKDeployment` | Interactive end-to-end deployment orchestrator |
| `New-TAKVirtualMachine` | Create a Hyper-V Gen 2 VM for Rocky Linux 9 |
| `Wait-TAKLinuxInstall` | Wait for OS install; establish SSH session |

### TAKInstall (6 cmdlets)

| Cmdlet | Purpose |
|--------|---------|
| `Install-TAKServer` | Install TAK Server 5.7 RPM via SSH |
| `New-TAKServerCertificate` | Create CA, server cert, client cert; configure CoreConfig.xml |
| `Set-TAKAdminCertificate` | Promote admin cert to administrator role |
| `Install-TAKOpenfire` | Install Openfire XMPP server |
| `New-TAKLetsEncryptCertificate` | Issue Let's Encrypt TLS cert |
| `Update-TAKLetsEncryptCertificate` | Renew Let's Encrypt TLS cert |

### TAKServerPS (44 cmdlets)

| Category | Cmdlets |
|----------|---------|
| **Session** | `Connect-TAKServer`, `Disconnect-TAKServer` |
| **Server** | `Get-TAKVersion` |
| **Users** | `Get-TAKUser`, `New-TAKUser`, `Remove-TAKUser`, `Set-TAKUserPassword`, `Set-TAKUserGroup` |
| **Groups** | `Get-TAKGroup` |
| **Subscriptions** | `Get-TAKSubscription`, `Remove-TAKSubscription` |
| **Contacts & CoT** | `Get-TAKContact`, `Get-TAKCoT` |
| **Certificates** | `Get-TAKCertificate`, `Remove-TAKCertificate`, `Invoke-TAKCertificateSign` |
| **Missions** | `Get-TAKMission`, `New-TAKMission`, `Remove-TAKMission`, `Get-TAKMissionChange`, `Get-TAKMissionContact`, `Get-TAKMissionSubscription`, `Register-TAKMissionSubscription`, `Unregister-TAKMissionSubscription` |
| **Inputs** | `Get-TAKInput`, `New-TAKInput`, `Remove-TAKInput` |
| **Data Feeds** | `Get-TAKDataFeed`, `New-TAKDataFeed`, `Remove-TAKDataFeed` |
| **Video** | `Get-TAKVideo`, `New-TAKVideo`, `Remove-TAKVideo` |
| **Outgoing** | `Get-TAKOutgoingConnection`, `New-TAKOutgoingConnection`, `Remove-TAKOutgoingConnection` |
| **Federation** | `Get-TAKFederate` |
| **Security** | `Get-TAKSecurityConfig`, `Set-TAKSecurityConfig`, `Remove-TAKToken` |
| **Plugins** | `Get-TAKPlugin` |
| **Map Layers** | `Get-TAKMapLayer`, `Remove-TAKMapLayer` |
| **Device Profiles** | `Get-TAKDeviceProfile` |
