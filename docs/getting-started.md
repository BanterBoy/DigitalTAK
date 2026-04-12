---
layout: page
title: Getting Started
nav_title: Getting Started
---

# Getting Started

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

You must download these separately before running a deployment. **They are not included in this repository and must not be committed.**

1. **Rocky Linux 9.7 ISO** — from [rockylinux.org](https://rockylinux.org/download)
2. **TAK Server 5.7 RPM** (`takserver-5.7-RELEASE8.noarch.rpm`) — from [tak.gov](https://tak.gov)
   - A free TAK.gov account is required
   - **MFA is enforced** on the downloads portal — enrol a second factor before attempting to download
   - Navigate to **Downloads → TAK Server** after logging in
   - The RPM is over 500 MB and is `.gitignore`d — never commit it to this repository

{: .warning }
If VS Code shows a **"Files too large"** warning when committing, click **Cancel**. The TAK Server RPM must not be committed to this repository.

### PowerShell Modules

Install the required PowerShell modules before using TAKInstall or running tests:

```powershell
# Required for SSH-based provisioning
Install-Module -Name Posh-SSH -Scope CurrentUser -Force

# Required for running unit tests
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force
```

> *Chuck Norris doesn't install `Posh-SSH`. SSH clients install themselves in his presence.*

---

## Cloning the Repository

```powershell
git clone https://github.com/BanterBoy/DigitalTAK.git
cd DigitalTAK
```

### Repository Layout

```
DigitalTAK/
├── Deploy-TAKServer.ps1        # Main entry point — full automated deployment
├── Deploy-TAKTestServer.ps1    # Backward-compat wrapper → Deploy-TAKServer.ps1
├── Invoke-TAKOnboarding.ps1    # Thin wrapper → TAKOnboarding\Invoke-TAKOnboarding
├── Invoke-TAKRollback.ps1      # Thin wrapper → TAKDeploy\Invoke-TAKRollback
├── Remove-CivTAK.ps1           # Thin wrapper → TAKDeploy\Remove-TAKDeployment
├── Invoke-UnitTests.ps1        # Run all Pester unit tests
├── Invoke-IntegrationTests.ps1 # Run integration tests (no live server required)
├── Invoke-E2ETests.ps1         # Run E2E tests against a live TAK Server
│
├── TAKServerPS/                # PowerShell REST API wrapper (44 cmdlets)
├── TAKInstall/                 # PowerShell SSH provisioning module (6 cmdlets)
├── TAKDeploy/                  # PowerShell Hyper-V orchestration module (5 cmdlets)
├── TAKOnboarding/              # PowerShell team onboarding module (3 cmdlets)
│
├── onboarding/                 # Team onboarding scripts and roster helpers
│   └── rosters/                # Sample CSV/JSON roster files
├── certs/                      # Downloaded team cert files (generated; git-ignored)
├── dist/                       # Per-user ATAK .zip data packages (generated; git-ignored)
│
├── InstallShellScripts/        # Bash scripts executed on the Rocky Linux guest
├── tests/integration/          # Pester 5 integration tests (no live server required)
├── tests/e2e/                  # E2E tests requiring a live TAK Server instance
│
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

Expected output: **179 unit tests, all passing**.

### Integration tests

A separate suite of integration tests validates the onboarding pipeline and teardown scripts without a live server:

```powershell
# Run integration tests (no TAK Server required)
Invoke-Pester ./tests/integration/ -Output Detailed
```

Expected: **45 integration tests pass**. Tests that require Administrator (Windows cert store writes) are automatically skipped in non-elevated sessions.

Total across all test suites: **224 tests, all passing**.

### E2E tests (live server required)

A separate E2E suite validates the full request/response cycle against a running TAK Server:

```powershell
# Set required environment variables
$env:TAK_INTEGRATION_HOST = '192.168.1.50'
$env:TAK_CERT_PASS        = 'YourCertPassword'

# Run the full E2E suite
.\Invoke-E2ETests.ps1
```

E2E tests require `certs/admin.p12` and a reachable TAK Server. See [tests/e2e/README.md](https://github.com/BanterBoy/DigitalTAK/blob/prod/tests/e2e/README.md) for full details.

### What the tests cover

| Module | Tests | Coverage |
|---|---|---|
| TAKServerPS | 109 | Module manifest, 44-function inventory, HTTP retry, auto-pagination, auth parameter sets |
| TAKInstall | 70 | Module manifest, 6-function inventory, bash escaping, SSH execution, service polling |
| Integration (09) | — | `Remove-CivTAK.ps1` Windows cert store cleanup (skipped without elevation) |
| Integration (10) | — | `New-TAKDataPackage.ps1` truststore lookup — `.jks` and `.p12` paths |
| Integration (11) | — | `Remove-CivTAK.ps1` filesystem teardown (Steps 4 / 4b) |
| E2E (01–06) | — | Server status, cert auth, CoT tracking, GeoChat, mission packages, negative/security cases |

---

## CI Pipeline

Every push to `prod` and all pull requests run the full CI pipeline via GitHub Actions:

| Job | Tool | What it checks |
|---|---|---|
| **Pester** | PowerShell | Unit tests across TAKServerPS, TAKInstall, TAKDeploy, TAKOnboarding + integration test infrastructure |
| **PSScriptAnalyzer** | PowerShell | Code quality and best practices |
| **ShellCheck** | Bash | Shell script linting (severity: warning) |

The GitHub Pages documentation site is built and deployed separately via `.github/workflows/pages.yml` on every push to `prod` that modifies `docs/**`.

See `.github/workflows/ci.yml` for the full pipeline definition.

---

## Quick-Start: TAKOnboarding Module

Once TAK Server is deployed, use the TAKOnboarding module for one-command team onboarding:

```powershell
Import-Module .\TAKOnboarding\TAKOnboarding.psd1

# Onboard a 10-person team — prompts for all credentials
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName alpha -TeamSize 10

# Custom roster from CSV
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo `
    -RosterPath .\onboarding\rosters\sample-roster-10.csv `
    -AdminPfxPath .\certs\admin.p12
```

For the full cmdlet reference, see [TAKOnboarding Module](modules/TAKOnboarding/).

---

## Quick-Start: TAKServerPS Module

Once you have a running TAK Server, use the REST API wrapper to manage it:

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1

# Connect using an admin PFX certificate (recommended)
$pass = Read-Host -AsSecureString 'Admin PFX password'
Connect-TAKServer -HostName "10.0.0.10" -PfxPath ".\admin.p12" -PfxPassword $pass -SkipCertificateCheck $true

# List all provisioned user accounts
Get-TAKUser -AccountList

# Get version info
Get-TAKVersion

# List missions
Get-TAKMission

# Disconnect
Disconnect-TAKServer
```

{: .note }
39 of 46 end-to-end tests pass against a live TAK Server 5.7-RELEASE8 instance (April 2026). `New-TAKUser` REST and `Set-TAKUserGroup` have a known server-side ESAPI bug — use `UserManager.jar` over SSH as the workaround. See the [Validation Report](../validation-report/) and [Troubleshooting](../troubleshooting/#symptom-new-takuser-or-set-takusergroup-returns-http-500--nullpointerexception) for details.

For the full cmdlet reference, see the [Agents & Skills Reference](../agents-skills-reference/) page or run `Get-Help <CmdletName> -Full` in PowerShell.

---

## Next Steps

- [Deploy a CivTAK Server](../deployment/) — full step-by-step guide
- [Agent Configuration](../agent-configuration/) — manage deployments using AI agents
- [Agents & Skills Reference](../agents-skills-reference/) — full module and cmdlet reference
