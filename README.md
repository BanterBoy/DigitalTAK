# DigitalTAK

CivTAK / TAK Server automation for Rocky Linux 9.  
Provides Bash shell scripts and two PowerShell modules (`TAKServerPS`, `TAKInstall`) to install, configure, and manage a production TAK Server 5.7 deployment — including certificate management, XMPP chat integration, Let's Encrypt TLS, and a full REST API wrapper.

**Target platform:** Rocky Linux 9.5 · Hyper-V Gen 2 · TAK Server `5.7-RELEASE8`

---

## Repository Structure

```
DigitalTAK/
├── Wiki/                       ← In-repo wiki section for operators and maintainers
├── InstallShellScripts/        ← Bash deployment scripts (run on the server)
├── TXTScripts/                 ← Byte-identical TXT mirrors of every .sh file
├── TAKServerPS/                ← PowerShell module — TAK Server REST API (44 cmdlets)
├── TAKInstall/                 ← PowerShell module — remote provisioning via SSH (6 cmdlets)
├── Documentation/              ← Official TAK Server 5.7 & Federation Hub guides (PDF)
├── channels.zip                ← ATAK client data package for device distribution
└── reports/                    ← Deployment and test reports
```

---

## General Deployment Script

The repository also includes a general Hyper-V deployment entry point:

- `Deploy-TAKServer.ps1` — canonical end-to-end deployment script for building a TAK Server VM from your own configuration
- `Deploy-TAKTestServer.ps1` — backward-compatible wrapper that forwards to `Deploy-TAKServer.ps1`

Use `Deploy-TAKServer.ps1` when you want to deploy a server from this repository using your own VM sizing, credentials, RPM path, certificate subject metadata, and snapshot-resume behavior.

Detailed operator guidance is in [Documentation/Deploy-TAKServer.md](Documentation/Deploy-TAKServer.md).

The repository wiki section for the deployment script and both PowerShell modules is in [Wiki/Home.md](Wiki/Home.md).

Quick start:

```powershell
Set-Location .
$cred = Get-Credential -UserName 'atak'
$rootPw = Read-Host -AsSecureString -Prompt 'Root password'
$ksPw = Read-Host -AsSecureString -Prompt 'TAK keystore password'

.\Deploy-TAKServer.ps1 `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
    -Confirm:$false
```

If you do not pass `-State`, `-City`, `-Organization`, `-OrganizationalUnit`, or `-CAName`, the script now prompts for them instead of silently applying fixed lab metadata.

---

## Bash Installation Scripts

Scripts live in `InstallShellScripts/`; byte-identical copies exist in `TXTScripts/` for environments that cannot execute `.sh` directly.

### Execution Order

```
1. RL9_tak5.7r8_install.sh           ← run as root — main TAK Server install
2. createTakCerts.sh                  ← interactive CA + server cert creation
       └── takUserCreateCerts_doNotRunAsRoot.sh   ← called automatically as the tak user
3. promoteAdmin.sh                    ← promote the admin cert to administrator role

[Optional]
   openfire_takChat_install.sh        ← Openfire XMPP / TAK Chat integration
   takserver_createLECerts.sh         ← one-time Let's Encrypt cert issuance
       └── takserver_renewLECerts.sh  ← renewal (schedule with cron)
```

### Script Reference

| Script | Purpose |
|--------|---------|
| `RL9_tak5.7r8_install.sh` | Installs PostgreSQL (pgdg), OpenJDK 17, TAK Server RPM + GPG key, configures SELinux policy and firewalld rules. |
| `createTakCerts.sh` | Prompts for STATE / CITY / ORG / OU and keystore password; creates Root CA, Intermediate CA, server cert, admin cert; patches `CoreConfig.xml` for x509 TLS + cert enrollment. |
| `takUserCreateCerts_doNotRunAsRoot.sh` | Called by `createTakCerts.sh` as the `tak` user; generates per-user client certificates. |
| `promoteAdmin.sh` | Promotes `admin.pem` to the TAK Server administrator role via the UserManager utility. |
| `openfire_takChat_install.sh` | Installs Openfire XMPP server, the TAK Server chat plugin, and configures firewalld for XMPP ports. |
| `takserver_createLECerts.sh` | Issues a Let's Encrypt certificate via Certbot and configures TAK Server to use it. |
| `takserver_renewLECerts.sh` | Renews the Let's Encrypt certificate and restarts TAK Server; designed to run from cron. |

### Prerequisites

- Rocky Linux 9 (fresh install recommended)
- `takserver-5.7-RELEASE8.noarch.rpm` — downloaded from [tak.gov](https://tak.gov) into the same directory as the scripts
- `takserver-public-gpg.key` — from tak.gov (optional — used for GPG signature verification)

---

## PowerShell Modules

Both modules require **PowerShell 7.0+** and follow Microsoft best practices — `CmdletBinding`, approved verbs, `ShouldProcess` on destructive operations, `SecureString` for passwords, and PSScriptAnalyzer-clean source.

### TAKServerPS — REST API Module

**Path:** `TAKServerPS/`  
**Manifest:** `TAKServer.psd1` · **Version:** 1.0.0

Wraps the TAK Server 5.x REST API. Authenticate once with `Connect-TAKServer`; all 44 cmdlets share the session automatically.

#### Installation

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1
```

#### Authentication

```powershell
# Certificate (recommended for production)
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('admin.p12', $pass)
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Certificate $cert

# PFX file shorthand
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -PfxPath '.\admin.p12' -PfxPassword $pass

# Username / password
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Credential (Get-Credential)

# Bearer token
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Token $secureToken
```

#### Cmdlet Reference

| Category | Cmdlets |
|----------|---------|
| **Session** | `Connect-TAKServer`, `Disconnect-TAKServer` |
| **Users** | `Get-TAKUser`, `New-TAKUser`, `Remove-TAKUser`, `Set-TAKUserPassword`, `Set-TAKUserGroup` |
| **Groups** | `Get-TAKGroup` |
| **Subscriptions** | `Get-TAKSubscription`, `Remove-TAKSubscription`, `Get-TAKContact` |
| **Missions** | `Get-TAKMission`, `New-TAKMission`, `Remove-TAKMission`, `Get-TAKMissionChange`, `Get-TAKMissionContact`, `Get-TAKMissionSubscription`, `Register-TAKMissionSubscription`, `Unregister-TAKMissionSubscription` |
| **Certificates** | `Get-TAKCertificate`, `Remove-TAKCertificate`, `Invoke-TAKCertificateSign` |
| **Data Feeds** | `Get-TAKDataFeed`, `New-TAKDataFeed`, `Remove-TAKDataFeed` |
| **Inputs** | `Get-TAKInput`, `New-TAKInput`, `Remove-TAKInput` |
| **Outgoing Connections** | `Get-TAKOutgoingConnection`, `New-TAKOutgoingConnection`, `Remove-TAKOutgoingConnection` |
| **CoT** | `Get-TAKCoT` |
| **Device Profiles** | `Get-TAKDeviceProfile` |
| **Map Layers** | `Get-TAKMapLayer`, `Remove-TAKMapLayer` |
| **Video** | `Get-TAKVideo`, `New-TAKVideo`, `Remove-TAKVideo` |
| **Plugins** | `Get-TAKPlugin` |
| **Federate** | `Get-TAKFederate` |
| **Security** | `Get-TAKSecurityConfig`, `Set-TAKSecurityConfig`, `Remove-TAKToken` |
| **Server** | `Get-TAKVersion` |

```powershell
# Examples
Get-TAKUser
New-TAKUser -Username 'jsmith' -Password $pass -Role 'ROLE_ANONYMOUS'
Get-TAKMission | Where-Object { $_.state -eq 'ACTIVE' }
Get-TAKCertificate | Where-Object { $_.expiration -lt (Get-Date).AddDays(30) }
Disconnect-TAKServer
```

---

### TAKInstall — Remote Provisioning Module

**Path:** `TAKInstall/`  
**Manifest:** `TAKInstall.psd1` · **Version:** 1.0.0  
**Requires:** [Posh-SSH](https://github.com/darkoperator/Posh-SSH)

Automates the full TAK Server deployment sequence over an SSH session — no manual server interaction required after the initial SSH connection. Mirrors every step performed by the Bash scripts.

#### Installation

```powershell
Install-Module Posh-SSH -Scope CurrentUser
Import-Module .\TAKInstall\TAKInstall.psd1
```

#### Usage Example — Full Deployment

```powershell
# 1. Open an SSH session to the Rocky Linux 9 server
$ssh  = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

# 2. Install TAK Server
Install-TAKServer -SshSession $ssh -RpmPath '/tmp/takserver-5.7-RELEASE8.noarch.rpm'

# 3. Create certificates
New-TAKServerCertificate -SshSession $ssh `
    -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' `
    -KeystorePassword $pass

# 4. Promote admin certificate
Set-TAKAdminCertificate -SshSession $ssh

# 5. (Optional) Install Openfire XMPP
Install-TAKOpenfire -SshSession $ssh

# 6. (Optional) Issue Let's Encrypt certificate
New-TAKLetsEncryptCertificate -SshSession $ssh -Domain 'tak.example.com' -Email 'admin@example.com'
```

#### Cmdlet Reference

| Cmdlet | Purpose |
|--------|---------|
| `Install-TAKServer` | Installs PostgreSQL, OpenJDK 17, TAK Server RPM, configures SELinux and firewalld. |
| `New-TAKServerCertificate` | Creates Root CA, Intermediate CA, server cert, admin + user client certs; patches `CoreConfig.xml` for x509 auth. |
| `Set-TAKAdminCertificate` | Promotes the admin client certificate to the TAK Server administrator role. |
| `Install-TAKOpenfire` | Installs Openfire XMPP server and the TAK Server chat plugin. |
| `New-TAKLetsEncryptCertificate` | Issues a Let's Encrypt certificate and configures TAK Server to use it. |
| `Update-TAKLetsEncryptCertificate` | Renews the Let's Encrypt certificate and restarts TAK Server. |

---

## Network Ports

| Port | Protocol | Service |
|------|----------|---------|
| 8089 | TCP / TLS | Cursor-on-Target (CoT) — client connections |
| 8443 | TCP / HTTPS | WebTAK UI · REST API · admin console |
| 8446 | TCP / HTTPS | Client certificate enrollment |
| 80   | TCP / HTTP | Certbot ACME challenge (Let's Encrypt only) |
| 5222 / 5223 | TCP | Openfire XMPP client |
| 5269 | TCP | Openfire XMPP server federation |
| 7070 / 7443 | TCP | Openfire HTTP binding |
| 7777 | TCP | Openfire TAK plugin |
| 9090 / 9091 | TCP | Openfire admin console |

---

## Tests

Both modules include Pester 5 unit tests in their `Tests/` subdirectories. All 179 tests pass. No live TAK Server or SSH host is required — all external calls are mocked.

```
TAKServerPS/Tests/
    TAKServerPS.Module.Tests.ps1      ← manifest + 44-function inventory (73 tests)
    Invoke-TAKRequest.Tests.ps1       ← HTTP helper unit tests (22 tests)
    Connect-TAKServer.Tests.ps1       ← auth parameter sets (19 tests)

TAKInstall/Tests/
    TAKInstall.Module.Tests.ps1       ← manifest + 6-function inventory (31 tests)
    ConvertTo-TAKBashArg.Tests.ps1    ← bash arg escaping (4 tests)
    Invoke-TAKRemoteCommand.Tests.ps1 ← SSH command executor (16 tests)
    Wait-TAKServiceReady.Tests.ps1    ← service polling helper (14 tests)
```

Run a single file to avoid memory pressure:

```powershell
Invoke-Pester -Path .\TAKServerPS\Tests\TAKServerPS.Module.Tests.ps1 -Output Detailed
```

Full results: [reports/TEST-REPORT.md](reports/TEST-REPORT.md)

---

## Documentation

| File | Description |
|------|-------------|
| `Wiki/Home.md` | Wiki index for deployment, `TAKInstall`, and `TAKServerPS` |
| `Wiki/Deploy-TAKServer.md` | Wiki page for the general deployment entry point |
| `Wiki/TAKInstall.md` | Wiki page for the SSH provisioning module and its exported functions |
| `Wiki/TAKServerPS.md` | Wiki page for the REST API module and its exported functions |
| `Wiki/_Sidebar.md` | Wiki navigation sidebar for the in-repo wiki section |
| `Documentation/TAK_Server_Configuration_Guide_5.7.pdf` | Official TAK Server 5.7 configuration guide |
| `Documentation/Federation_Hub_Configuration_Guide.pdf` | Federation Hub configuration and setup guide |
| `channels.zip` | ATAK client data package — distribute to devices via TAK Server data packages |
| `reports/TEST-REPORT.md` | Pester test results with per-test breakdown and bug fix notes |

---

## References

- [TAK Server downloads and documentation — tak.gov](https://tak.gov)
- [Posh-SSH module — github.com/darkoperator/Posh-SSH](https://github.com/darkoperator/Posh-SSH)
- [ATAK (Android Team Awareness Kit) — tak.gov/products/atak](https://tak.gov/products/atak)
