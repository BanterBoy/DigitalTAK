---
layout: page
title: TAKDeploy Module
nav_title: TAKDeploy
---

# TAKDeploy Module

**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** `Posh-SSH`, `Hyper-V`

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

## Gaps and Known Issues

- No automated Rocky Linux installation (Kickstart/unattended) — the operator must complete the graphical installer manually.
- `New-TAKVirtualMachine` does not validate that the ISO is a valid Rocky Linux image before booting.
- `Wait-TAKLinuxInstall` relies on Hyper-V's IP detection via `Get-VMNetworkAdapter`; IP detection may fail if Hyper-V guest services are not running. The operator is prompted to enter the IP manually in that case.
