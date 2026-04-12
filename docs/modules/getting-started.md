---
layout: page
title: Getting Started (Modules)
nav_title: Module Guide
---

# Getting Started: End-to-End TAK Server Deployment

This guide covers a typical deployment from a Windows Hyper-V host to a fully operational TAK Server 5.7.

---

## Overview

The DigitalTAK PowerShell pipeline involves three modules:

| Module | Purpose |
|--------|---------|
| **TAKDeploy** | Create Hyper-V VM, wait for Rocky Linux install, hand off SSH session |
| **TAKInstall** | Remote-provision TAK Server on Rocky Linux 9 over SSH |
| **TAKServerPS** | Manage a running TAK Server via its REST API |

TAKDeploy orchestrates TAKInstall. TAKServerPS is used independently after the server is running.

---

## Prerequisites

### Operator workstation

- Windows 10/11 or Windows Server 2019+ with Hyper-V role enabled
- PowerShell 7.0 or later
- `Posh-SSH` module:
  ```powershell
  Install-Module Posh-SSH -Scope CurrentUser
  ```
- At least one External Hyper-V virtual switch (or a physical NIC to create one — TAKDeploy handles this interactively)

### Files required

- **Rocky Linux 9 DVD ISO** — download from rockylinux.org
- **TAK Server 5.7-RELEASE8 RPM** (`takserver-5.7-RELEASE8.noarch.rpm`) — obtained from [tak.gov](https://tak.gov)
- *(optional)* TAK Server GPG key (`takserver-public-gpg.key`) — from tak.gov
- *(optional)* `takserver_renewLECerts.sh` — included in this repository, required for Let's Encrypt

---

## Option A: Fully Automated (Recommended)

Use `Start-TAKDeployment` for a guided, end-to-end interactive deployment. It collects configuration upfront and orchestrates all phases automatically.

```powershell
# 1. Import the module (elevated PowerShell required)
Import-Module .\TAKDeploy\TAKDeploy.psd1

# 2. Start the interactive deployment
Start-TAKDeployment
```

The wizard will prompt for:
- VM name, path, ISO and RPM locations, hardware specs
- Org details for certificate subject (State, City, Org, OU — must be uppercase)
- Keystore password
- Whether to install Openfire XMPP
- Whether to configure Let's Encrypt (requires a public FQDN)

After the deployment completes, the console prints:

```
  VM:         TAKServer (192.168.1.50)
  WebTAK:     https://192.168.1.50:8443
  CoT:        192.168.1.50:8089 (TLS)
  Cert Enrol: https://192.168.1.50:8446

  Admin cert: /home/atak/admin.p12
  Import this into your browser to access WebTAK admin.
```

### If you already have a Rocky Linux VM

```powershell
Start-TAKDeployment -SkipVMCreation
```

This skips Hyper-V VM creation (Phases 1 and 1b) and prompts directly for the server's IP address and SSH credentials.

---

## Option B: Step by Step

Use the individual module cmdlets for more control.

### Step 1 — Create the VM

```powershell
Import-Module .\TAKDeploy\TAKDeploy.psd1

New-TAKVirtualMachine `
    -VMName 'TAKServer' `
    -IsoPath 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso' `
    -VHDSizeGB 80 `
    -MemoryStartupBytes 8GB `
    -ProcessorCount 4

# Open the Hyper-V console and install Rocky Linux
vmconnect.exe $env:COMPUTERNAME TAKServer
```

Rocky Linux installation checklist:
1. Set a root password
2. Create a sudo-capable user (e.g. `atak`)
3. Configure networking (DHCP or static)
4. Select **Minimal Install**
5. Complete installation and reboot

### Step 2 — Establish SSH session

```powershell
$session = Wait-TAKLinuxInstall -VMName 'TAKServer' -TimeoutSeconds 600
```

### Step 3 — Install TAK Server

```powershell
Import-Module .\TAKInstall\TAKInstall.psd1

$cred = Get-Credential -Message 'SSH credentials (same as Step 2)'

Install-TAKServer `
    -SshSession $session `
    -RpmPath '.\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential $cred
```

### Step 4 — Create certificates

```powershell
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

New-TAKServerCertificate `
    -SshSession $session `
    -State 'TX' `
    -City 'AUSTIN' `
    -Organization 'MYORG' `
    -OrganizationalUnit 'OPS' `
    -KeystorePassword $pass
```

### Step 5 — Promote admin certificate

```powershell
Set-TAKAdminCertificate -SshSession $session
```

Retrieve `/home/atak/admin.p12` from the server and import it into your browser (Chrome/Firefox: Settings → Certificates → Import). This certificate authenticates you to the WebTAK admin interface at `https://<server-ip>:8443`.

### Step 6 — (Optional) Install Openfire XMPP

```powershell
Install-TAKOpenfire -SshSession $session
```

After installation, browse to `http://<server-ip>:9090` and complete the Openfire setup wizard before using TAK Chat in ATAK/WinTAK.

### Step 7 — (Optional) Configure Let's Encrypt

> Requires a public IP with a DNS A record pointing to the server, and port 80 open from the internet.

```powershell
New-TAKLetsEncryptCertificate `
    -SshSession $session `
    -DomainName 'tak.example.com' `
    -KeystorePassword $pass `
    -RenewalScriptPath '.\takserver_renewLECerts.sh'
```

---

## Creating User Certificates

After the server is running, create client certificates for ATAK/WinTAK users by SSH-ing to the server:

```bash
ssh atak@<server-ip>
/opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
```

The script creates a `.p12` file in `/opt/tak/certs/files/` for distribution to the user's device.

---

## Managing a Running Server

Use `TAKServerPS` to manage the server via its REST API.

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1

# Connect (certificate auth using admin.p12)
Connect-TAKServer -HostName '192.168.1.50' `
    -PfxPath 'C:\certs\admin.p12' `
    -PfxPassword (Read-Host -AsSecureString)

# Check version
Get-TAKVersion

# List connected users
Get-TAKUser

# Create a new user
$cred = Get-Credential -UserName 'fielduser1'
New-TAKUser -Credential $cred -GroupList 'Operators'

# Create a mission
New-TAKMission -Name 'OpBlue' -Description 'Operation Blue' -Group 'TeamAlpha'

# List active subscriptions
Get-TAKSubscription

# End session
Disconnect-TAKServer
```

---

## Port Reference

| Port | Protocol | Service |
|------|----------|---------|
| 8443 | TCP/TLS | WebTAK HTTPS / REST API |
| 8089 | TCP/TLS | CoT (Cursor-on-Target) — client connections |
| 8446 | TCP/TLS | Certificate enrollment |
| 80 | TCP | Let's Encrypt ACME challenge (temporary) |
| 5222 | TCP | XMPP client (STARTTLS) — Openfire |
| 5223 | TCP | XMPP client (Direct TLS) — Openfire |
| 7070 | TCP | Openfire HTTP binding |
| 7443 | TCP | Openfire HTTPS binding |
| 7777 | TCP | Openfire file transfer proxy |
| 9090 | TCP | Openfire admin console (HTTP) |
| 9091 | TCP | Openfire admin console (HTTPS) |
