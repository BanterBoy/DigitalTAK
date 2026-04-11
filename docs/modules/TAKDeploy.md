---
layout: page
title: TAKDeploy Module
nav_title: TAKDeploy
---

# TAKDeploy Module

**Version:** 1.1.0
**PowerShell:** 7.0+
**Required modules:** `Posh-SSH`

## Purpose

TAKDeploy provides cmdlets for creating a Hyper-V Gen 2 virtual machine running Rocky Linux 9 and orchestrating end-to-end TAK Server deployment on that VM. It shells out to TAKInstall over SSH once the OS is installed.

## Prerequisites

- Windows host with Hyper-V enabled (elevated PowerShell required for VM creation)
- PowerShell 7.0 or later
- `Posh-SSH` module: `Install-Module Posh-SSH -Scope CurrentUser`
- Rocky Linux 9 DVD ISO (`Rocky-9.x-x86_64-dvd.iso`)
- TAK Server 5.7-RELEASE8 RPM (`takserver-5.7-RELEASE8.noarch.rpm`) — obtained from tak.gov
- At least one External Hyper-V virtual switch (or a physical NIC to create one)

## Installing

```powershell
Import-Module .\TAKDeploy\TAKDeploy.psd1
```

## Cmdlet Reference

### `Start-TAKDeployment`

**Synopsis:** Interactive orchestrator that deploys TAK Server from scratch on Hyper-V.

Runs the full deployment pipeline in phases:

| Phase | Description |
|-------|-------------|
| 0 | Collect configuration interactively; check prerequisites |
| 1 | Create Hyper-V Gen 2 VM and boot Rocky Linux ISO |
| 1b | Wait for operator to complete Rocky Linux install; establish SSH |
| 2a | `Install-TAKServer` — install RPM, Java, SELinux, firewall |
| 2b | `New-TAKServerCertificate` — create CA chain and server cert |
| 2c | `Set-TAKAdminCertificate` — promote admin cert |
| 2d | *(optional)* `Install-TAKOpenfire` |
| 2e | *(optional)* `New-TAKLetsEncryptCertificate` |
| 3 | Print deployment summary with access URLs |

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SkipVMCreation` | Switch | No | Skip Phase 1/1b; prompts for existing VM's IP and SSH credentials |

**Examples:**

```powershell
# Full interactive deployment
Start-TAKDeployment

# Skip VM creation — provision onto an existing Rocky Linux VM
Start-TAKDeployment -SkipVMCreation
```

---

### `New-TAKVirtualMachine`

**Synopsis:** Creates a Hyper-V Gen 2 virtual machine configured for Rocky Linux 9.

Creates and starts the VM. Open the Hyper-V console to complete the OS installation, then call `Wait-TAKLinuxInstall`.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `TAKServer` | Name of the VM in Hyper-V Manager |
| `VMPath` | String | `C:\Hyper-V\VMs` | Directory for VM configuration and VHDX |
| `IsoPath` | String | `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso` | Path to Rocky Linux 9 DVD ISO |
| `VHDSizeGB` | Int | `80` | Dynamic VHDX size in GB (min 20, max 2048) |
| `MemoryStartupBytes` | Long | `8GB` | Fixed memory allocation in bytes (dynamic memory disabled) |
| `ProcessorCount` | Int | `4` | Number of virtual processors (max 64) |
| `SwitchName` | String | *(auto-detected)* | Hyper-V External virtual switch name |

**Outputs:** `Microsoft.HyperV.PowerShell.VirtualMachine`

**Notes:**
- Requires an elevated (Administrator) PowerShell session.
- If no External vSwitch exists, the cmdlet offers to create one using the first active physical NIC. Network connectivity will briefly drop during switch creation.
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = High`).

**Examples:**

```powershell
# Create VM with all defaults
New-TAKVirtualMachine

# Custom VM with 120 GB disk and 8 vCPUs
New-TAKVirtualMachine -VMName 'TAK-Lab' -VHDSizeGB 120 -ProcessorCount 8

# Open the console to install Rocky Linux
vmconnect.exe $env:COMPUTERNAME TAKServer
```

---

### `Wait-TAKLinuxInstall`

**Synopsis:** Waits for the Rocky Linux installation to complete and establishes an SSH session.

Pauses for the operator to complete the OS install via the Hyper-V console, then auto-detects the VM's IP address and retries SSH until the connection succeeds or the timeout expires.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `TAKServer` | Name of the Hyper-V VM to monitor |
| `TimeoutSeconds` | Int | `300` | Maximum seconds to attempt SSH (30–3600) |
| `RetryIntervalSeconds` | Int | `10` | Seconds between SSH attempts (5–120) |
| `Credential` | PSCredential | *(prompted)* | SSH credentials; prompted interactively if not supplied |

**Outputs:** `SSH.SshSession`

**Examples:**

```powershell
# Wait for install, get session, pass to Install-TAKServer
$session = Wait-TAKLinuxInstall -VMName 'TAKServer'
Install-TAKServer -SshSession $session -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm'

# Use a 10-minute SSH retry timeout
$session = Wait-TAKLinuxInstall -VMName 'TAK-Lab' -TimeoutSeconds 600
```

---

---

### `Remove-TAKDeployment`

**Synopsis:** Fully removes a CivTAK deployment from Hyper-V and the local machine.

Performs a complete teardown in six steps:

1. *(optional)* SSH into the VM and run `tak-uninstall.sh` to cleanly uninstall TAK Server from the guest OS (`-UninstallGuest`)
2. Stop and remove the Hyper-V VM and all its snapshots
3. Delete the VHDX disk file
4. Remove all cert/key files from `certs\` (recursive, covers team subdirectories)
5. Remove ATAK data packages from `dist\`
6. Remove imported TAK certificates from the Windows certificate store

This cmdlet is **idempotent** — re-running on an already-cleaned deployment is safe.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `CivTAK` | Name of the Hyper-V VM to remove |
| `VHDPath` | String | *(auto)* | Path of the VHDX to delete. Defaults to `C:\Hyper-V\VMs\<VMName>\<VMName>.vhdx` |
| `UninstallGuest` | Switch | Off | SSH into the running VM and run `tak-uninstall.sh` before destroying it. Requires `-Credential` |
| `Credential` | PSCredential | *(none)* | Linux admin SSH credential. Required when `-UninstallGuest` is set |
| `Organization` | String | `TAK` | Organisation string used to scope Windows cert store cleanup. Must match the value used during deployment |
| `CAName` | String | `TAK-CA` | Root CA name used during deployment. Used to identify and remove root CA, intermediate CA, and admin certs from the Windows store |
| `DeploymentRoot` | String | *(cwd)* | Root folder of the DigitalTAK repo. Used to locate `certs\`, `dist\`, and `InstallShellScripts\tak-uninstall.sh` |

**Notes:**
- Requires an elevated (Administrator) PowerShell session for Hyper-V and Windows cert store operations.
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = High`).

**Examples:**

```powershell
# Full teardown with all defaults
Remove-TAKDeployment

# Custom org/CA name matching deployment parameters
Remove-TAKDeployment -Organization 'LEIGH-SERVICES' -CAName 'TAK-CA'

# Clean uninstall from guest before VM destruction
$cred = Get-Credential -UserName 'atak'
Remove-TAKDeployment -UninstallGuest -Credential $cred

# Remove a named VM with an explicit VHDX path
Remove-TAKDeployment -VMName 'CivTAK-Prod' -VHDPath 'D:\VMs\CivTAK-Prod\CivTAK-Prod.vhdx'
```

---

### `Invoke-TAKRollback`

**Synopsis:** Rolls back a CivTAK Hyper-V deployment to a known-good Phase snapshot.

Lists all deployment Phase snapshots for the target VM (created by `Start-TAKDeployment`) and restores either the specified snapshot or the most recent one. After rollback, the VM is started and SSH connectivity is confirmed.

Available snapshots (created automatically by `Start-TAKDeployment`):

| Snapshot | Description |
|----------|-------------|
| `Phase0-RockyInstalled` | Rocky Linux OS installed, SSH working |
| `Phase2-TAKInstalled` | TAK Server RPM installed and running |
| `Phase4-CertsAndAdmin` | Certificates created, admin promoted |

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VMName` | String | `CivTAK` | Name of the Hyper-V VM to roll back |
| `SnapshotName` | String | *(most recent)* | Exact snapshot name to restore (e.g. `Phase0-RockyInstalled`). If omitted, the most recent deployment snapshot is used |
| `ListOnly` | Switch | Off | List available deployment snapshots without restoring any |
| `SSHTimeoutSeconds` | Int | `120` | Seconds to wait for SSH after restore |

**Notes:**
- Supports `-WhatIf` / `-Confirm`.
- After rollback, `Start-TAKDeployment` re-run will resume from the appropriate phase.

**Examples:**

```powershell
# Restore the most recent deployment snapshot
Invoke-TAKRollback

# List available snapshots without restoring
Invoke-TAKRollback -ListOnly

# Roll back to a specific phase
Invoke-TAKRollback -SnapshotName 'Phase0-RockyInstalled'

# Roll back a named VM to a specific phase
Invoke-TAKRollback -VMName 'CivTAK-Prod' -SnapshotName 'Phase2-TAKInstalled'
```

---

## Gaps and Known Issues

- No automated Rocky Linux installation (Kickstart/unattended) — the operator must complete the graphical installer manually.
- `New-TAKVirtualMachine` does not validate that the ISO is a valid Rocky Linux image before booting.
- `Wait-TAKLinuxInstall` relies on Hyper-V's IP detection via `Get-VMNetworkAdapter`; IP detection may fail if Hyper-V guest services are not running. The operator is prompted to enter the IP manually in that case.
