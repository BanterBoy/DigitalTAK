---
layout: default
title: TAK Server Deployment
nav_order: 3
---

# TAK Server Deployment
{: .no_toc }

Step-by-step guide for deploying a CivTAK server using `Deploy-CivTAK.ps1`.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

`Deploy-CivTAK.ps1` is the canonical entry point for a complete, zero-touch CivTAK deployment. It:

- Creates a Hyper-V Gen 2 VM and installs Rocky Linux 9 via kickstart
- Installs and configures TAK Server 5.7 over SSH
- Creates a full certificate authority, server certs, and client certs
- Promotes the admin certificate
- Runs a post-deploy smoke test
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
- [ ] Rocky Linux 9.5 DVD ISO downloaded (default expected path: `C:\Hyper-V\ISO\Rocky-9.5-x86_64-dvd.iso`)
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

.\Deploy-CivTAK.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw
```

You will be prompted for:
- **State** — e.g., `TX`
- **City** — e.g., `AUSTIN`
- **Organization** — e.g., `ACME-OPS`
- **Organizational Unit** — e.g., `TAK`
- **CA Name** — e.g., `ACME-TAK-CA`

---

## Fully Parameterised Invocation

For non-interactive / scripted deployments:

```powershell
$cred   = [PSCredential]::new('atak', (ConvertTo-SecureString 'IamGroot.3742' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString 'R00t!Secure42' -AsPlainText -Force
$ksPw   = ConvertTo-SecureString 'T@kServ3r2025!' -AsPlainText -Force

.\Deploy-CivTAK.ps1 `
    -VMName           'CivTAK-Prod' `
    -RockyIsoPath     'D:\ISO\Rocky-9.5-x86_64-dvd.iso' `
    -RpmPath          'D:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential       $cred `
    -RootPassword     $rootPw `
    -KeystorePassword $ksPw `
    -State            'TX' -City 'AUSTIN' `
    -Organization     'ACME-OPS' -OrganizationalUnit 'TAK' `
    -CAName           'ACME-TAK-CA' `
    -Confirm:$false
```

---

## Deployment Phases

The script executes in 10 phases. A Hyper-V snapshot is taken after key phases so the deployment can be resumed safely.

| Phase | Name | What Happens | Snapshot Created? |
|-------|------|-------------|:-----------------:|
| 0 | Prerequisites | Checks Hyper-V, PowerShell version, required files | No |
| 1 | Create VM | Hyper-V Gen 2 VM created, Rocky Linux kickstart delivered via OEMDRV VHDX | No |
| 2 | OS Install | Waits for Rocky Linux unattended install and SSH availability | **Yes** — `Phase0-RockyInstalled` |
| 3 | TAK Install | Installs TAK Server RPM, configures SELinux and firewalld | **Yes** — `Phase2-TAKInstalled` |
| 4 | Create Certs | Creates CA, server certificates, client certificates, patches CoreConfig.xml | **Yes** — `Phase4-CertsAndAdmin` |
| 5 | Promote Admin | Promotes admin.pem to TAK Server administrator | No |
| 6 | Smoke Test | Connects to REST API, validates version endpoint | No |
| 7 | Download Certs | Transfers .p12 client certificates via SFTP | No |
| 8 | Import Certs | Imports .p12 into Windows certificate store | No |
| 9 | Report | Generates deployment report in `reports/` | No |

{: .note }
Phase numbers in snapshot names refer to the phase that **completed**, not the phase about to run. For example, `Phase0-RockyInstalled` means Phase 0 (wait for OS) finished successfully.

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-VMName` | string | `CivTAK` | Hyper-V VM name |
| `-SwitchName` | string | *(auto-detect)* | Hyper-V virtual switch. First External switch used if omitted |
| `-RockyIsoPath` | string | `C:\Hyper-V\ISO\Rocky-9.5-x86_64-dvd.iso` | Path to Rocky Linux 9 DVD ISO |
| `-VHDPath` | string | *(derived from VMName)* | Path for the dynamic VHDX |
| `-VHDSizeBytes` | int64 | `80 GB` | Maximum VHDX size |
| `-MemoryBytes` | int64 | `8 GB` | Fixed RAM assigned to the VM |
| `-ProcessorCount` | int | `4` | Number of virtual CPUs |
| `-Credential` | PSCredential | **(mandatory)** | Linux admin account (username + password) |
| `-RootPassword` | SecureString | **(mandatory)** | Root account password |
| `-KeystorePassword` | SecureString | **(mandatory)** | TAK Server keystore password (min 6 chars) |
| `-RpmPath` | string | `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm` | Path to TAK Server RPM |
| `-SshPublicKey` | string | *(empty)* | Optional SSH public key for admin user |
| `-State` | string | *(prompted)* | Certificate subject state |
| `-City` | string | *(prompted)* | Certificate subject city |
| `-Organization` | string | *(prompted)* | Certificate subject organisation |
| `-OrganizationalUnit` | string | *(prompted)* | Certificate subject OU |
| `-CAName` | string | *(prompted)* | Certificate authority name |
| `-Timezone` | string | `Europe/London` | Guest OS IANA timezone |
| `-Hostname` | string | `takserver` | Guest OS hostname |
| `-Keyboard` | string | `gb` | X keyboard variant |
| `-Lang` | string | `en_GB.UTF-8` | Guest OS locale |
| `-SSHTimeoutSeconds` | int | `900` | Max wait (seconds) for SSH after OS install |
| `-DisableSnapshotResume` | switch | *(off)* | Force clean rebuild, ignore existing snapshots |

---

## Resuming a Failed Deployment

If a deployment fails mid-way, simply re-run the same command. The script automatically detects the latest phase snapshot and resumes from that point:

```powershell
# Re-run with the same credentials — resumes from last checkpoint automatically
.\Deploy-CivTAK.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw
```

To force a complete rebuild from scratch:

```powershell
.\Deploy-CivTAK.ps1 -DisableSnapshotResume -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw
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
.\Invoke-TAKRollback.ps1 -VMName 'CivTAK-Prod' -SnapshotName 'Phase2-TAKInstalled'
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

Default admin credentials are set during the Promote Admin phase. Import the downloaded `.p12` certificate from `reports/certs/` into your ATAK client.
