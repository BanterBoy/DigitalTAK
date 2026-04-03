---
layout: page
title: Agents & Skills Reference
nav_title: Agents & Skills
---

# Agents & Skills Reference
{: .no_toc }

Complete reference for all PowerShell modules, cmdlets, and Bash scripts in DigitalTAK.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## PowerShell Modules

DigitalTAK provides three PowerShell modules that layer from infrastructure to application:

| Module | Cmdlets | Layer | Requires |
|--------|---------|-------|---------|
| **TAKDeploy** | 3 | Hyper-V VM orchestration | PowerShell 7+, Hyper-V |
| **TAKInstall** | 6 | Remote SSH provisioning | PowerShell 7+, Posh-SSH |
| **TAKServerPS** | 44 | TAK Server REST API | PowerShell 7+, running TAK Server |

---

## TAKDeploy

Manages Hyper-V virtual machine lifecycle for DigitalTAK deployments.

**Import:** `Import-Module ./TAKDeploy`

### Cmdlets

#### `New-TAKVirtualMachine`
Creates a Hyper-V Gen 2 VM and delivers a Rocky Linux kickstart via an OEMDRV VHDX.

```powershell
New-TAKVirtualMachine `
    -VMName      'CivTAK' `
    -SwitchName  'ExternalSwitch' `
    -IsoPath     'C:\ISO\Rocky-9.7-x86_64-dvd.iso' `
    -VMPath      'C:\Hyper-V\VMs\CivTAK' `
    -VHDSizeGB    80 `
    -MemoryStartupBytes 8GB
```

#### `Wait-TAKLinuxInstall`
Polls the VM until the Rocky Linux unattended installation completes and SSH becomes available.

```powershell
Wait-TAKLinuxInstall -VMName 'CivTAK' -TimeoutSeconds 900
```

#### `Start-TAKDeployment`
Reserved internal scaffolding. `Deploy-TAKServer.ps1` calls `New-TAKVirtualMachine` and `Wait-TAKLinuxInstall` directly and does not use this cmdlet.

---

## TAKInstall

Provisions a TAK Server on a remote Rocky Linux host over SSH.

**Import:** `Import-Module ./TAKInstall`
**Dependency:** `Posh-SSH` module

### Cmdlets

#### `Install-TAKServer`
Copies the TAK Server RPM to the remote host and installs it via the `RL9_tak5.7r8_install.sh` script. Configures SELinux and firewalld.

```powershell
$session = New-SSHSession -ComputerName '10.0.0.10' -Credential $cred -AcceptKey

Install-TAKServer `
    -SshSession  $session `
    -RpmPath     'C:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential  $cred
```

#### `New-TAKServerCertificate`
Creates a certificate authority, server certificate, and client certificates. Patches `CoreConfig.xml` with the new certificate paths.

```powershell
New-TAKServerCertificate `
    -SshSession        $session `
    -KeystorePassword  $ksPw `
    -State             'TX' `
    -City              'AUSTIN' `
    -Organization      'ACME-OPS' `
    -OrganizationalUnit 'TAK' `
    -CAName            'ACME-TAK-CA'
```

#### `Set-TAKAdminCertificate`
Promotes the generated `admin.pem` to TAK Server administrator role.

```powershell
Set-TAKAdminCertificate -SshSession $session
```

#### `Install-TAKOpenfire`
Installs and configures Openfire XMPP server with TAK Chat integration.

```powershell
Install-TAKOpenfire -SshSession $session
```

#### `New-TAKLetsEncryptCertificate`
Issues a Let's Encrypt certificate via Certbot. Requires a public DNS record and port 80 open.

```powershell
$pass = Read-Host -AsSecureString 'Keystore password'
New-TAKLetsEncryptCertificate `
    -SshSession         $session `
    -DomainName         'tak.example.com' `
    -KeystorePassword   $pass `
    -RenewalScriptPath  '.\InstallShellScripts\takserver_renewLECerts.sh'
```

#### `Update-TAKLetsEncryptCertificate`
Renews an existing Let's Encrypt certificate. Suitable for use in a scheduled task.

```powershell
Update-TAKLetsEncryptCertificate -SshSession $session
```

---

## TAKServerPS

REST API wrapper for TAK Server 5.7. Provides 44 cmdlets covering all major TAK Server API endpoints.

**Import:** `Import-Module ./TAKServerPS`

### Session Management

#### `Connect-TAKServer`
Establishes an authenticated session to TAK Server. Stores the session in module state.

```powershell
# PFX file (recommended)
Connect-TAKServer -HostName '10.0.0.10' -PfxPath '.\admin.p12' -PfxPassword $pw -SkipCertificateCheck $true

# Credential auth
Connect-TAKServer -HostName '10.0.0.10' -Port 8443 -Credential (Get-Credential) -SkipCertificateCheck $true

# Certificate object
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('admin.p12', $pw)
Connect-TAKServer -HostName '10.0.0.10' -Certificate $cert -SkipCertificateCheck $true
```

{: .note }
`-SkipCertificateCheck $true` is the default and expected for self-signed deployments.

#### `Disconnect-TAKServer`
Closes the current TAK Server session and clears module state.

```powershell
Disconnect-TAKServer
```

---

### User Management

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKUser` | List all users or get a specific user |
| `New-TAKUser` | Create a new user account |
| `Remove-TAKUser` | Delete a user account |
| `Set-TAKUserPassword` | Change a user's password |
| `Set-TAKUserGroup` | Assign a user to a group |

```powershell
# List all users
Get-TAKUser

# Create a user (use -InboundGroups/-OutboundGroups for data-direction group assignment)
New-TAKUser -Credential (Get-Credential) -InboundGroups 'team-alpha' -OutboundGroups 'team-alpha'

# Remove a user
Remove-TAKUser -Username 'operator1'
```

---

### Group Management

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKGroup` | List all groups or get a specific group |

---

### Mission Management

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKMission` | List missions |
| `New-TAKMission` | Create a mission |
| `Remove-TAKMission` | Delete a mission |
| `Get-TAKMissionSubscription` | List mission subscriptions |
| `Register-TAKMissionSubscription` | Subscribe to a mission |
| `Unregister-TAKMissionSubscription` | Unsubscribe from a mission |
| `Get-TAKMissionChange` | Get mission change log |
| `Get-TAKMissionContact` | List contacts associated with a mission |

---

### Certificate Management

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKCertificate` | List enrolled certificates |
| `Remove-TAKCertificate` | Revoke a certificate |
| `Invoke-TAKCertificateSign` | Sign a certificate signing request |

---

### Server & Configuration

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKVersion` | Get server version information |
| `Get-TAKSecurityConfig` | Get security configuration |
| `Set-TAKSecurityConfig` | Update security configuration |
| `Remove-TAKToken` | Remove a token |

---

### Data & Connections

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKDataFeed` | List data feeds |
| `New-TAKDataFeed` | Create a data feed |
| `Remove-TAKDataFeed` | Remove a data feed |
| `Get-TAKInput` | List inputs |
| `New-TAKInput` | Create an input |
| `Remove-TAKInput` | Remove an input |
| `Get-TAKOutgoingConnection` | List outgoing connections |
| `New-TAKOutgoingConnection` | Create an outgoing connection |
| `Remove-TAKOutgoingConnection` | Remove an outgoing connection |

---

### Device & Client

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKDeviceProfile` | List device profiles |
| `Get-TAKCoT` | Get Cursor-on-Target events |
| `Send-TAKCoT` | Send a CoT event |
| `Get-TAKMapLayer` | List map layers |
| `Remove-TAKMapLayer` | Remove a map layer |
| `Get-TAKContact` | List contacts |
| `Get-TAKSubscription` | List subscriptions |
| `Remove-TAKSubscription` | Remove a subscription |

---

### Video & Plugins

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKVideo` | List video feeds |
| `New-TAKVideo` | Add a video feed |
| `Remove-TAKVideo` | Remove a video feed |
| `Get-TAKPlugin` | List installed plugins |

---

### Federation

| Cmdlet | Description |
|--------|-------------|
| `Get-TAKFederate` | List federation connections |

---

## Bash Scripts (InstallShellScripts/)

These scripts run on the Rocky Linux 9 guest. They are executed remotely by TAKInstall via SSH. Do not run them directly on your Windows host.

| Script | Description |
|--------|-------------|
| `RL9_tak5.7r8_install.sh` | Main TAK Server installer: pgdg, OpenJDK 17, RPM, SELinux, firewalld |
| `createTakCerts.sh` | CA + server cert creation, CoreConfig.xml patching |
| `takUserCreateCerts_doNotRunAsRoot.sh` | Per-user client cert generation (runs as `tak` user) |
| `promoteAdmin.sh` | Promotes `admin.pem` to TAK administrator role |
| `openfire_takChat_install.sh` | Optional: Openfire XMPP server + TAK Chat integration |
| `takserver_createLECerts.sh` | Optional: Let's Encrypt cert issuance via Certbot |
| `takserver_renewLECerts.sh` | Optional: Let's Encrypt cert renewal (cron-friendly) |
| `tak-uninstall.sh` | Full removal: TAK Server, PostgreSQL, Openfire |
| `utils.sh` | Shared helpers: `bash_quote()`, `sed_replace_quote()`, `wait_for_service()` |

{: .note }
Every `.sh` file has a byte-identical `.txt` mirror in `TXTScripts/`. This is enforced by CI. If you modify a shell script, run `.\Sync-TXTMirrors.ps1` to update the mirrors.

---

## Top-Level Scripts

| Script | Description |
|--------|-------------|
| `Deploy-TAKServer.ps1` | Main entry point — full zero-to-running CivTAK deployment |
| `Invoke-TAKRollback.ps1` | Roll back VM to a phase snapshot |
| `Remove-CivTAK.ps1` | Tear down VM, VHDX, certs, and Windows certificate store entries |
| `Invoke-IntegrationTests.ps1` | Run end-to-end integration tests (requires live `TAK_INTEGRATION_HOST`) |
| `Deploy-TAKTestServer.ps1` | Test deployment wrapper |
| `Sync-TXTMirrors.ps1` | Sync `.txt` mirrors of all `.sh` files |

---

## Integration Tests

End-to-end Pester tests run via `Invoke-IntegrationTests.ps1`. Require a live TAK Server at `$env:TAK_INTEGRATION_HOST`.

| Test File | What It Tests |
|-----------|--------------|
| `01-VMProvisioning.Tests.ps1` | VM creation, kickstart delivery, OEMDRV disk |
| `02-OSInstall.Tests.ps1` | Rocky Linux installation, SSH connectivity |
| `03-TAKServerHealth.Tests.ps1` | TAK Server service health, REST API readiness |
| `04-Certificates.Tests.ps1` | Certificate generation, CoreConfig.xml, admin promotion |
| `05-UserManagement.Tests.ps1` | User CRUD, group assignments, authentication |

```powershell
# Run integration tests (requires live server)
$env:TAK_INTEGRATION_HOST = '10.0.0.10'
.\Invoke-IntegrationTests.ps1
```
