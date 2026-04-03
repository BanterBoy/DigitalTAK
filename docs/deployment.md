---
layout: page
title: TAK Server Deployment
nav_title: Deployment
---

# TAK Server Deployment
{: .no_toc }

Step-by-step guide for deploying a CivTAK server using `Deploy-TAKServer.ps1`.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

`Deploy-TAKServer.ps1` is the canonical entry point for a complete, zero-touch CivTAK deployment. It:

- Creates a Hyper-V Gen 2 VM and installs Rocky Linux 9 via kickstart
- Installs and configures TAK Server 5.7 over SSH
- Creates a full certificate authority, server certs, and client certs
- Promotes the admin certificate
- Runs 20 post-deployment validation tests (service health, ports, SELinux, firewall, certs)
- Downloads `.p12` client certificates to your local machine
- Imports certificates into the Windows certificate store
- Generates a deployment report

**Re-running is safe.** The script detects existing phase snapshots and resumes from the latest checkpoint. You never need to start from scratch after a partial failure.

---

## Prerequisites Checklist

Before running the deployment:

- [ ] Windows 10/11 Pro or Windows Server 2019+ with Hyper-V enabled
- [ ] PowerShell 7.0+ running **as Administrator**
- [ ] `Posh-SSH` module installed: `Install-Module Posh-SSH -Scope CurrentUser -Force`
- [ ] Hyper-V virtual switch named `TAK-External` (External type) — or supply `-SwitchName`
- [ ] Rocky Linux 9 DVD ISO downloaded (default expected path: `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso`)
- [ ] TAK Server 5.7 RPM downloaded from [tak.gov](https://tak.gov) (default: `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm`)
- [ ] At least 40 GB free disk space for the VM VHDX (default: 80 GB dynamic)
- [ ] At least 8 GB RAM available for the VM

---

## Minimal Invocation

The simplest deployment uses all defaults and prompts interactively for certificate subject fields:

```powershell
# Run from the repo root as Administrator
$cred   = Get-Credential -UserName 'atak'
$rootPw = Read-Host -AsSecureString 'Root password'
$ksPw   = Read-Host -AsSecureString 'Keystore password'
$certPw = Read-Host -AsSecureString 'Certificate (.p12) password'

.\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
```

You will be prompted for:
- **State** — e.g., `ESSEX`
- **City** — e.g., `SOUTHEND-ON-SEA`
- **Organization** — e.g., `LEIGH-SERVICES`
- **Organizational Unit** — e.g., `IT-DEPARTMENT`
- **CA Name** — e.g., `TAK-CA`

---

## Fully Parameterised Invocation

For non-interactive / scripted deployments:

```powershell
$cred   = [PSCredential]::new('atak', (ConvertTo-SecureString 'IamGroot.3742' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString 'R00t!Secure42' -AsPlainText -Force
$ksPw   = ConvertTo-SecureString 'T@kServ3r2025!' -AsPlainText -Force
$certPw = ConvertTo-SecureString 'C3rtP@ss2025!' -AsPlainText -Force

.\Deploy-TAKServer.ps1 `
    -VMName           'TAK-Prod-01' `
    -SwitchName       'External LAN' `
    -RockyIsoPath     'D:\ISO\Rocky-9.7-x86_64-dvd.iso' `
    -RpmPath          'D:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential       $cred `
    -RootPassword     $rootPw `
    -KeystorePassword $ksPw `
    -CertPassword     $certPw `
    -State            'TX' -City 'AUSTIN' `
    -Organization     'ACME-OPS' -OrganizationalUnit 'TAK' `
    -CAName           'ACME-TAK-CA' `
    -Confirm:$false
```

---

## Deployment Phases

The script executes in 9 phases. A Hyper-V snapshot is taken after key phases so the deployment can be resumed safely.

| Phase | Name | What Happens | Snapshot Created? |
|-------|------|-------------|:-----------------:|
| 0 | Create VM | Hyper-V Gen 2 VM created, Rocky Linux kickstart delivered via OEMDRV VHDX | **Yes** — `Phase0-RockyInstalled` |
| 1 | SSH | Establishes SSH session to the new VM | No |
| 2 | TAK Install | Installs TAK Server RPM, configures SELinux and firewalld | **Yes** — `Phase2-TAKInstalled` |
| 3 | Create Certs | Creates CA, server certificates, client certificates, patches CoreConfig.xml | No |
| 4 | Promote Admin | Promotes admin.pem to TAK Server administrator | **Yes** — `Phase4-CertsAndAdmin` |
| 5 | Validation | 20 post-deployment tests (service, ports, firewall, certs, SELinux, OS) | No |
| 6 | Download Certs | Transfers `.p12` client certificates via SFTP | No |
| 7 | Import Certs | Imports `.p12` into Windows certificate store | No |
| 8 | Report | Generates deployment report in `reports/` | No |

{: .note }
Snapshot names are legacy labels; they do not correspond 1-to-1 to the phase numbers in the table above.

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-VMName` | string | `TAKServer` | Hyper-V VM name |
| `-SwitchName` | string | `TAK-External` | Hyper-V virtual switch. Must already exist |
| `-RockyIsoPath` | string | `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso` | Path to Rocky Linux 9 DVD ISO |
| `-VHDPath` | string | `C:\Hyper-V\VMs\TAKServer\TAKServer.vhdx` | Path for the dynamic VHDX |
| `-VHDSizeBytes` | int64 | `80 GB` | Maximum VHDX size |
| `-MemoryBytes` | int64 | `8 GB` | Fixed RAM assigned to the VM |
| `-ProcessorCount` | int | `4` | Number of virtual CPUs |
| `-Credential` | PSCredential | **(mandatory)** | Linux admin account (username + password) |
| `-RootPassword` | SecureString | **(mandatory)** | Root account password |
| `-KeystorePassword` | SecureString | **(mandatory)** | TAK Server keystore password (min 6 chars) |
| `-CertPassword` | SecureString | **(mandatory)** | PKCS#12 (.p12) certificate password |
| `-RpmPath` | string | `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm` | Path to TAK Server RPM |
| `-State` | string | *(prompted, default: ESSEX)* | Certificate subject state |
| `-City` | string | *(prompted, default: SOUTHEND-ON-SEA)* | Certificate subject city |
| `-Organization` | string | *(prompted, default: LEIGH-SERVICES)* | Certificate subject organisation |
| `-OrganizationalUnit` | string | *(prompted, default: IT-DEPARTMENT)* | Certificate subject OU |
| `-CAName` | string | *(prompted, default: TAK-CA)* | Certificate authority name |
| `-Timezone` | string | `Europe/London` | Guest OS IANA timezone |
| `-Hostname` | string | `takserver` | Guest OS hostname |
| `-SSHTimeoutSeconds` | int | `600` | Max wait (seconds) for SSH after OS install |
| `-DisableSnapshotResume` | switch | *(off)* | Force clean rebuild, ignore existing snapshots |

---

## Resuming a Failed Deployment

If a deployment fails mid-way, simply re-run the same command. The script automatically detects the latest phase snapshot and resumes from that point:

```powershell
# Re-run with the same credentials — resumes from last checkpoint automatically
.\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
```

To force a complete rebuild from scratch:

```powershell
.\Deploy-TAKServer.ps1 -DisableSnapshotResume -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw
```

---

## Rolling Back to a Previous Phase

Use `Invoke-TAKRollback.ps1` to restore the VM to a known-good phase snapshot:

```powershell
# List available snapshots
.\Invoke-TAKRollback.ps1 -ListOnly

# Roll back to the most recent snapshot
.\Invoke-TAKRollback.ps1

# Roll back to a specific phase
.\Invoke-TAKRollback.ps1 -SnapshotName 'Phase0-RockyInstalled'

# Roll back a named VM to a specific phase
.\Invoke-TAKRollback.ps1 -VMName 'TAK-Prod-01' -SnapshotName 'Phase2-TAKInstalled'
```

Available snapshot names:

| Snapshot | State |
|----------|-------|
| `Phase0-RockyInstalled` | Rocky Linux installed, SSH working |
| `Phase2-TAKInstalled` | TAK Server RPM installed and running |
| `Phase4-CertsAndAdmin` | Certificates created, admin promoted |

---

## Optional: Openfire XMPP Chat

After deployment, you can add XMPP chat support via Openfire using the TAKInstall module:

```powershell
Import-Module ./TAKInstall

$session = New-SSHSession -ComputerName <VM-IP> -Credential $cred -AcceptKey
Install-TAKOpenfire -SSHSession $session
Remove-SSHSession -SSHSession $session
```

---

## Optional: Let's Encrypt TLS

To replace the self-signed certificate with a publicly trusted cert:

```powershell
Import-Module ./TAKInstall

$session = New-SSHSession -ComputerName <VM-IP> -Credential $cred -AcceptKey
New-TAKLetsEncryptCertificate -SSHSession $session -Domain 'tak.example.com' -Email 'admin@example.com'
Remove-SSHSession -SSHSession $session
```

{: .warning }
Let's Encrypt requires a **public DNS record** pointing to the VM and **port 80 open** for the ACME HTTP challenge. This is not required for a private network deployment.

---

## Tearing Down a Deployment

To completely remove the VM, certificates, and Windows certificate store entries:

```powershell
.\Remove-CivTAK.ps1
```

By default this preserves the TAK Server install on the guest. To uninstall TAK from the guest before destroying the VM:

```powershell
.\Remove-CivTAK.ps1 -UninstallGuest
```

{: .warning }
`Remove-CivTAK.ps1` is **irreversible**. The VM VHDX and all snapshots are deleted. Ensure you have exported any data you need before running this.

---

## Post-Deployment Access

Once the deployment completes:

| Interface | URL / Address |
|-----------|---------------|
| **WebTAK UI** | `https://<VM-IP>:8443/webtak` |
| **Admin Console** | `https://<VM-IP>:8443/` |
| **REST API** | `https://<VM-IP>:8443/` |
| **CoT (ATAK clients)** | `<VM-IP>:8089` |
| **Client cert enrollment** | `https://<VM-IP>:8446` |

Default admin credentials are set during the Promote Admin phase. Import the downloaded `.p12` certificate from `certs/` into your ATAK client.

---

## Live Deployment Validation (DIG-53, 2026-04-03)

The full end-to-end deployment was validated against a live Rocky Linux 9.7 Hyper-V VM (10.10.0.144).
**22 / 22 core health checks passed.** Zero failures.

### Validated Hardware Specs

These are the minimum-recommended specs confirmed to run a production deployment without issue:

| Resource | Value |
|----------|-------|
| vCPU | 4 |
| RAM | 8 GB (fixed) |
| VHD | 80 GB dynamic VHDX |
| Disk used at idle | ~4 GB / 48 GB provisioned (9%) |
| OS | Rocky Linux 9.7 (Blue Onyx) |
| Java | OpenJDK 17.0.18 LTS |
| TAK Server | takserver-5.7-RELEASE8.noarch |

### Deployment Timing

| Phase | Approx Duration |
|-------|----------------|
| Total (all phases) | ~14 minutes |
| Install TAK Server | ~3m 28s |
| Create Certificates | ~1m 55s |
| Promote Admin Cert | ~1m 12s |

### Known Gotchas

**Port 8443 returns connection failure during automated tests.** TAK Server enforces mutual TLS (mTLS). A bare HTTPS request without a client certificate gets an SSL handshake rejection (HTTP 000). This is *correct behaviour*, not a service failure. To verify manually, import `admin.p12` into your browser and navigate to `https://<VM-IP>:8443`.

**Port 8446 returns HTTP 403 for unauthenticated requests.** This is also correct — the certificate enrollment endpoint requires a valid client identity. The 403 confirms the service is up and correctly gating access.

**API management tests are skipped without `admin.p12` on the host.** The `05-UserManagement` and `08-GroupManagement` integration test suites require `certs/admin.p12` to be present locally. These are skipped automatically when the file is absent. To run them, retrieve the file first:

```powershell
scp atak@<VM-IP>:/home/atak/admin.p12 .\certs\admin.p12
```

**OpenSSL 3.x (Rocky Linux 9) and RC2-40-CBC PKCS#12 files.** The upstream TAK Server cert tooling produces PKCS#12 files encrypted with the legacy RC2-40-CBC cipher. OpenSSL 3.x (included in Rocky Linux 9) requires the `-legacy` flag to read these directly on the guest. This is a server-side inspection issue only — the `.p12` files are valid and import correctly into Windows without any workaround.

**PKCS#12 password.** The generated `.p12` files (`admin.p12`, `user.p12`, `truststore-intermediate-ca.p12`) use the upstream default password `atakatak`, regardless of the `-KeystorePassword` supplied to the deployment script. The keystore password governs the server-side JKS stores; the PKCS#12 password is set separately by the TAK cert generation tools.

### Test Infrastructure Fixes Applied

Several test infrastructure issues were identified and fixed during DIG-53 validation. If you maintain a fork, ensure these changes are present:

| Issue | Fix |
|-------|-----|
| `Test-TAKTCPPort -Host` shadows the PowerShell `$Host` automatic variable | Parameter renamed to `-HostName` |
| `Invoke-IntegrationTests.ps1` / `Invoke-E2ETests.ps1` fail when run outside the repo root (`$PSScriptRoot` empty) | Default path resolution moved into script body |
| `Invoke-Pester -Configuration ... -Passthru` incompatible with Pester 5.7 | Use `$config.Run.PassThru = $true` instead |
| `05-UserManagement` / `08-GroupManagement`: Pester 5 evaluates `-Skip:` at discovery time, causing `CommandNotFoundException` when `admin.p12` is absent | Tests now use `Set-ItResult -Skipped` inside test bodies (runtime check) |
