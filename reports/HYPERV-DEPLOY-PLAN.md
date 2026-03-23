# TAK Server Hyper-V Deployment Script — Design Plan

**Date:** 2026-03-23 (updated)  
**Author:** GitHub Copilot (DigitalTAK Orchestrator mode)  
**Status:** DRAFT — Environment verified, open questions resolved, ready for implementation

---

## 1. Goal

Create an interactive PowerShell deployment script that:

1. **Creates** a Hyper-V Gen 2 VM from the Rocky Linux 9.7 DVD ISO.
2. **Waits** for the operator to complete the Rocky Linux installation via Hyper-V console.
3. **Connects** to the newly installed VM via SSH (Posh-SSH).
4. **Runs** the existing `TAKInstall` module cmdlets to install and configure TAK Server end-to-end.

The script bridges the gap between "bare metal" (no VM exists) and "TAK Server ready" — the full pipeline that currently requires manual Hyper-V setup, then separate PowerShell sessions to call `Install-TAKServer`, `New-TAKServerCertificate`, and `Set-TAKAdminCertificate`.

---

## 2. Known Environment (Verified 2026-03-23)

| Item | Value | Verified |
|------|-------|----------|
| Host OS | Windows 11 (AzureAD-joined) | Yes |
| PowerShell | 7.6.0 | Yes |
| Hyper-V feature | **Enabled** (`Microsoft-Hyper-V-All`) | Yes |
| Hyper-V module | 2.0.0.0 | Yes |
| ISO path | `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso` (~12.4 GB) | Yes — file exists |
| VM storage path | `C:\Hyper-V\VMs\` (empty — no existing VMs) | Yes |
| Disk free | **763 GB** on `C:` | Yes |
| Current user | `AzureAD\LukeLeigh` | Yes |
| Hyper-V Admins group | **Empty** — script must run elevated (RunAsAdministrator) | Yes |
| Existing vSwitches | **Default Switch** (Internal only) — no External switch exists | Yes |
| Active physical NIC | `Ethernet 2` — Intel I219-LM, 1 Gbps, Up | Yes |
| Other NICs | WiFi (Intel BE200, disconnected), Realtek USB GbE (disconnected) | Yes |
| Posh-SSH | 3.2.7 installed | Yes |
| TAKInstall module | 1.0.0 — 6 cmdlets, loads cleanly | Yes |
| TAK RPM | `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm` (562 MB) | Yes |

---

## 3. Proposed Folder Structure

```
DigitalTAK/
└── TAKDeploy/
    ├── TAKDeploy.psd1                  ← Module manifest
    ├── TAKDeploy.psm1                  ← Module loader (dot-sources Public/)
    ├── Public/
    │   ├── New-TAKVirtualMachine.ps1   ← Phase 1: Create Hyper-V VM
    │   ├── Start-TAKDeployment.ps1     ← Phase 2: Orchestrator (interactive, calls all phases)
    │   └── Wait-TAKLinuxInstall.ps1    ← Phase 1b: Wait for Rocky install + first SSH
    ├── Private/
    │   ├── Assert-HyperVPrerequisites.ps1  ← Checks: elevation, Hyper-V role, module, vSwitch
    │   └── Get-TAKDeploymentConfig.ps1     ← Interactive prompts → config hashtable
    └── Tests/
        ├── TAKDeploy.Module.Tests.ps1
        └── New-TAKVirtualMachine.Tests.ps1
```

---

## 4. Script Phases (Interactive Flow)

### Phase 0 — Prerequisites Check (`Assert-HyperVPrerequisites`)

Verify before doing anything:

| Check | Current state | Action if missing |
|-------|---------------|-------------------|
| Running as Administrator | **Pass** (confirmed) | Throw terminating error with instructions |
| Hyper-V role enabled | **Pass** (enabled) | `Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All` — throw if disabled |
| Hyper-V PowerShell module | **Pass** (2.0.0.0) | `Get-Module -ListAvailable Hyper-V` — throw if missing |
| At least one External vSwitch | **FAIL** — only Default Switch (Internal) | **Must create one** — prompt operator to select physical NIC (`Ethernet 2` is the only active NIC) |
| Posh-SSH module | **Pass** (3.2.7) | `Get-Module -ListAvailable Posh-SSH` — offer to install if missing |
| TAKInstall module | **Pass** (1.0.0) | `Import-Module ..\TAKInstall` — throw if not found |
| ISO exists | **Pass** (12.4 GB) | `Test-Path $IsoPath` |
| TAK RPM exists | **Pass** (562 MB) | `Test-Path $RpmPath` |

### Phase 1 — Create VM (`New-TAKVirtualMachine`)

Interactive prompts (with sensible defaults):

| Parameter | Default | Notes |
|-----------|---------|-------|
| `VMName` | `'TAKServer'` | Name in Hyper-V Manager |
| `VMPath` | `'C:\Hyper-V\VMs'` | Storage location |
| `IsoPath` | `'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso'` | Rocky DVD ISO |
| `VHDSizeGB` | `80` | Dynamic VHDX |
| `MemoryStartupBytes` | `8GB` | Fixed (no dynamic memory) |
| `ProcessorCount` | `4` | vCPUs |
| `SwitchName` | Auto-detected External switch | Or prompt if multiple |
| `Generation` | `2` | UEFI/Gen2 required for Rocky 9 |

Hyper-V cmdlets used:

```powershell
New-VM -Name $VMName -Generation 2 -Path $VMPath -MemoryStartupBytes 8GB -NewVHDPath ... -NewVHDSizeBytes 80GB -SwitchName $SwitchName
Set-VM -Name $VMName -ProcessorCount 4 -AutomaticCheckpointsEnabled $false -CheckpointType Standard
Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
Add-VMDvdDrive -VMName $VMName -Path $IsoPath
$dvd = Get-VMDvdDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
Enable-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface'
Start-VM -Name $VMName
```

> **Key:** Gen 2 + `MicrosoftUEFICertificateAuthority` Secure Boot template is required for Linux. The standard Microsoft template only boots Windows.

### Phase 1b — Wait for Rocky Linux Install (`Wait-TAKLinuxInstall`)

This is the **manual gap**. The operator must:

1. Open Hyper-V Manager (or `vmconnect.exe $env:COMPUTERNAME $VMName`).
2. Complete the Rocky Linux 9.7 installer:
   - Set root password.
   - Create the `atak` user (or another sudo-capable user).
   - Configure network (DHCP or static).
   - Select "Minimal Install" server with standard packages.
   - Enable SSH (should be on by default).
3. Reboot into the installed OS.

The script will:

```
Write-Host "══════════════════════════════════════════════════════════════"
Write-Host "  Rocky Linux installer is running in the VM console."
Write-Host "  Complete the installation, then press ENTER here when the"
Write-Host "  VM has rebooted and you can see a login prompt."
Write-Host "══════════════════════════════════════════════════════════════"
Read-Host "Press ENTER to continue"
```

Then attempt SSH connectivity:

- Prompt for the VM's IP address (or try to detect via `Get-VMNetworkAdapter -VMName $VMName | Select-Object -ExpandProperty IPAddresses`).
- Prompt for SSH credentials (`Get-Credential`).
- Loop: `New-SSHSession -ComputerName $ip -Credential $cred -AcceptKey` with retry + timeout.
- Once SSH is up, proceed to Phase 2.

### Phase 2 — TAK Server Deployment (`Start-TAKDeployment`)

Orchestrates the existing TAKInstall cmdlets in sequence, collecting all inputs upfront:

| Step | Cmdlet | Inputs needed |
|------|--------|--------------|
| 2a | `Install-TAKServer` | `-SshSession`, `-RpmPath`, optionally `-GpgKeyPath` |
| 2b | `New-TAKServerCertificate` | `-SshSession`, `-State`, `-City`, `-Organization`, `-OrganizationalUnit`, `-CAName`, `-KeystorePassword` |
| 2c | `Set-TAKAdminCertificate` | `-SshSession` |
| 2d *(optional)* | `Install-TAKOpenfire` | `-SshSession`, `-OpenAdminPorts` |
| 2e *(optional)* | `New-TAKLetsEncryptCertificate` | `-SshSession`, `-DomainName`, `-KeystorePassword`, `-RenewalScriptPath` |

Interactive prompts for cert metadata:

```
State abbreviation [e.g. TX]: 
City [e.g. AUSTIN]: 
Organisation [e.g. MYORG]: 
Organisational unit [e.g. OPS]: 
CA name [default: TAK-CA]: 
Keystore password: ********
Install Openfire XMPP chat? [Y/n]: 
Configure Let's Encrypt? [y/N]: 
```

### Phase 3 — Summary & Next Steps

After all phases complete, print:

```
══════════════════════════════════════════════════════════════
  TAK Server deployment complete!
  
  VM:        TAKServer (192.168.1.50)
  WebTAK:    https://192.168.1.50:8443
  CoT:       192.168.1.50:8089 (TLS)
  Cert Enrol: https://192.168.1.50:8446
  
  Admin cert: /home/atak/admin.p12
  → Import this into your browser to access WebTAK admin.
  
  To create user certificates, SSH to the server and run:
    /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
══════════════════════════════════════════════════════════════
```

---

## 5. Design Decisions (Resolved)

All open questions from the original draft have been resolved based on the verified environment.

### D1 — Elevation strategy → **(a) Require RunAsAdministrator**

Hyper-V cmdlets require Administrator privileges. The Hyper-V Administrators group is empty, so the script must be launched from an elevated PowerShell session. The script will check `([Security.Principal.WindowsPrincipal]...).IsInRole('Administrator')` and throw a terminating error with instructions if not elevated. No self-elevation via `Start-Process`.

### D2 — VM network configuration → **(c) Auto-detect + offer to create**

**Verified:** Only the `Default Switch` (Internal) exists. No External vSwitch is configured. The only active physical NIC is `Ethernet 2` (Intel I219-LM, 1 Gbps).

The script will:
1. Check for an existing External vSwitch.
2. If none found, list available physical NICs and prompt the operator to select one.
3. Create the External vSwitch with `-AllowManagementOS $true` (preserves host connectivity).
4. If exactly one active physical NIC exists (current state), auto-select it with confirmation.

### D3 — TAK RPM location → **(c) Parameter with default + prompt**

**Verified:** No `.rpm` file found anywhere on disk. The RPM must be downloaded from tak.gov before running.

Parameter `-RpmPath` defaults to `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm`. If the file doesn't exist at runtime, the script throws with a clear message directing the operator to download from tak.gov.

### D4 — Unattended Rocky Linux install → **(a) Manual install for v1**

Manual Anaconda installation via Hyper-V console. The script pauses with instructions and waits for the operator to confirm the install is complete. Kickstart automation is a future enhancement.

### D5 — Openfire and Let's Encrypt → **(a) Opt-in within main flow**

Interactive prompts during the orchestrator: `Install Openfire XMPP chat? [Y/n]` and `Configure Let's Encrypt? [y/N]`.

### D6 — Module or standalone script → **(a) New TAKDeploy module**

Consistent with TAKInstall and TAKServerPS conventions. Testable with Pester. Module dot-sources `Private/` then `Public/`.

### D7 — VM hardware defaults → **Parameters with sensible defaults**

Defaults: 8 GB fixed RAM, 80 GB dynamic VHDX, 4 vCPU, Gen 2. All exposed as parameters for override. No dynamic memory (Java heap sizing). No GPU passthrough.

---

## 6. Dependencies

| Dependency | Required by | Install method | Status |
|------------|-------------|----------------|--------|
| Hyper-V Windows Feature | VM creation | `Enable-WindowsOptionalFeature` (reboot required) | **Installed** |
| Hyper-V PowerShell module | VM creation | Comes with the Hyper-V feature | **v2.0.0.0** |
| Posh-SSH | SSH to VM after install | `Install-Module Posh-SSH -Scope CurrentUser` | **v3.2.7** |
| TAKInstall module | TAK provisioning | Already in this repo | **v1.0.0** |
| TAK Server RPM | TAK installation | Download from tak.gov (not redistributable) | **Present** at `C:\Hyper-V\AtakCiv\` |
| Rocky Linux 9.7 DVD ISO | OS installation | Download from rockylinux.org | **Present** at `C:\Hyper-V\ISO\` |
| External vSwitch | VM networking | Script creates if missing (uses `Ethernet 2` NIC) | **Must create** |

---

## 7. Estimated Deliverables

| File | Purpose |
|------|---------|
| `TAKDeploy/TAKDeploy.psd1` | Module manifest |
| `TAKDeploy/TAKDeploy.psm1` | Module loader |
| `TAKDeploy/Public/New-TAKVirtualMachine.ps1` | Create + configure Hyper-V VM |
| `TAKDeploy/Public/Wait-TAKLinuxInstall.ps1` | Wait for OS install, establish SSH |
| `TAKDeploy/Public/Start-TAKDeployment.ps1` | Full interactive orchestrator |
| `TAKDeploy/Private/Assert-HyperVPrerequisites.ps1` | Pre-flight checks |
| `TAKDeploy/Private/Get-TAKDeploymentConfig.ps1` | Interactive config wizard |
| `TAKDeploy/Tests/TAKDeploy.Module.Tests.ps1` | Module structure tests |
| `TAKDeploy/Tests/New-TAKVirtualMachine.Tests.ps1` | VM creation tests (mocked) |

---

## 8. SSH User Strategy (from TAK Server Configuration Guide §4.2, §21)

Per the official TAK Server 5.7 Configuration Guide:

1. **Rocky Linux install** creates a `root` account and a standard user account (e.g. `atak`).
2. **SSH connection** uses the standard user account with `sudo` for privileged operations.
3. **Certificate generation** runs as the `tak` user (`sudo su tak`) — this user is created by the TAK Server RPM.
4. **Admin promotion** uses `sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/admin.pem`.

The script will prompt for SSH credentials at runtime via `Get-Credential`. The TAKInstall module cmdlets already handle `sudo` elevation in their remote commands.

A text version of the configuration guide is now available at `Documentation/TAK_Server_Configuration_Guide_5.7.md` for agent reference.

---

## 9. Remaining Items Before Implementation

The environment is fully verified. All prerequisites are met.

| # | Item | Status |
|---|------|--------|
| 1 | **TAK RPM** | **Found** at `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm` (562 MB) |

### All other items resolved:

| Item | Resolution |
|------|------------|
| vSwitch | No External switch exists. Script will create one using `Ethernet 2` (Intel I219-LM). |
| SSH user | Standard practice per TAK manual — root + sudo user created during Rocky install. Script prompts for credentials. |
| Static IP or DHCP | Script tries `Get-VMNetworkAdapter` IP detection first, prompts if not found. DHCP expected for initial setup. |
| Elevation | Running as Administrator confirmed. Script uses `#Requires -RunAsAdministrator`. |
| All D1–D7 | Resolved — see Section 5. |

**All prerequisites met — ready to implement.**
