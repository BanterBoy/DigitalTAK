---
layout: default
title: Getting Started
nav_order: 2
---

# Getting Started
{: .no_toc }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

Before cloning and running the project, ensure your host machine meets these requirements:

### Host System Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows 10/11 Pro or Windows Server 2019+ |
| **Hyper-V** | Enabled (Windows Feature) |
| **PowerShell** | 7.0 or later |
| **RAM** | Minimum 8 GB free for the VM (16 GB host recommended) |
| **Disk** | Minimum 40 GB free for the VM VHDX |
| **Network** | Internal or External Hyper-V switch available |

### Required Files (Not Included in Repo)

You must download these separately before running a deployment:

1. **Rocky Linux 9.5 ISO** — from [rockylinux.org](https://rockylinux.org/download)
2. **TAK Server 5.7 RPM** — from [tak.gov](https://tak.gov) (requires a TAK.gov account)

### PowerShell Modules

Install the required PowerShell modules before using TAKInstall or running tests:

```powershell
# Required for SSH-based provisioning
Install-Module -Name Posh-SSH -Scope CurrentUser -Force

# Required for running unit tests
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force
```

---

## Cloning the Repository

```powershell
git clone https://github.com/BanterBoy/DigitalTAK.git
cd DigitalTAK
```

### Repository Layout

```
DigitalTAK/
├── Deploy-CivTAK.ps1           # Main entry point — full automated deployment
├── Invoke-TAKRollback.ps1      # Roll back to a deployment phase snapshot
├── Remove-CivTAK.ps1           # Tear down and clean up everything
├── Invoke-IntegrationTests.ps1 # Run end-to-end integration tests
├── Sync-TXTMirrors.ps1         # Maintain .txt mirrors of .sh files (CI helper)
│
├── TAKServerPS/                # PowerShell REST API wrapper (44 cmdlets)
├── TAKInstall/                 # PowerShell SSH provisioning module (6 cmdlets)
├── TAKDeploy/                  # PowerShell Hyper-V orchestration module (3 cmdlets)
│
├── InstallShellScripts/        # Bash scripts executed on the Rocky Linux guest
├── TXTScripts/                 # Byte-identical .txt mirrors of all .sh files
│
├── IntegrationTests/           # End-to-end Pester tests (requires live host)
├── Documentation/              # TAK Server PDF and Markdown guides
├── docs/                       # This documentation site
└── .github/workflows/          # GitHub Actions CI/CD pipelines
```

---

## Running the Unit Tests

Unit tests run against mocked dependencies — no live TAK Server or VM required.

```powershell
# Run all unit tests
Invoke-Pester ./TAKServerPS/Tests/ -Output Detailed
Invoke-Pester ./TAKInstall/Tests/ -Output Detailed
```

Expected output: **173 tests, all passing**.

### What the tests cover

| Module | Tests | Coverage |
|---|---|---|
| TAKServerPS | 103 | Module manifest, 44-function inventory, HTTP retry, auto-pagination, auth parameter sets |
| TAKInstall | 70 | Module manifest, 6-function inventory, bash escaping, SSH execution, service polling |

---

## CI Pipeline

Every push to `prod` and all pull requests run the full CI pipeline via GitHub Actions:

| Job | Tool | What it checks |
|---|---|---|
| **Pester** | PowerShell | 173 unit tests across TAKServerPS + TAKInstall |
| **PSScriptAnalyzer** | PowerShell | Code quality and best practices |
| **ShellCheck** | Bash | Shell script linting (severity: warning) |
| **TXT Sync** | Bash | .txt mirrors byte-identical to .sh files |

See `.github/workflows/ci.yml` for the full pipeline definition.

---

## Quick-Start: TAKServerPS Module

Once you have a running TAK Server, use the REST API wrapper to manage it:

```powershell
Import-Module ./TAKServerPS

# Connect (self-signed certs are the norm)
Connect-TAKServer -HostName "10.0.0.10" -Credential (Get-Credential) -SkipCertificateCheck

# List users
Get-TAKUser

# Create a user
New-TAKUser -Credential (Get-Credential) -InboundGroups "team-alpha" -OutboundGroups "team-alpha"

# List missions
Get-TAKMission

# Disconnect
Disconnect-TAKServer
```

For the full cmdlet reference, see the [Agents & Skills Reference](agents-skills-reference) page or run `Get-Help <CmdletName> -Full` in PowerShell.

---

## Next Steps

- [Deploy a CivTAK Server](deployment) — full step-by-step guide
- [Agent Configuration](agent-configuration) — manage deployments using AI agents
- [Agents & Skills Reference](agents-skills-reference) — full module and cmdlet reference
