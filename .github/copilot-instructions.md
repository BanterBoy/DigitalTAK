# DigitalTAK — Copilot Instructions

TAK Server 5.7-RELEASE8 automation for Rocky Linux 9 / Hyper-V Gen 2.
Two PowerShell modules + a set of Bash scripts provide the full install, cert, and API surface.

---

## Repository Layout

| Path | Purpose |
|------|---------|
| `TAKServerPS/` | PS module — 44-cmdlet REST API wrapper (PowerShell → TAK Server) |
| `TAKInstall/` | PS module — remote provisioning over SSH via Posh-SSH |
| `TAKDeploy/` | PS module — Hyper-V VM creation + deployment orchestration (3 cmdlets) |
| `InstallShellScripts/` | Bash scripts run directly on the Rocky 9 server |
| `onboarding/` | Team onboarding assets — cert batch script, roster helpers, data-package builder |
| `scripts/` | Standalone PS scripts |
| `tests/e2e/` | E2E Pester tests incl. `07-OnboardingFlow.Tests.ps1` (formerly `scripts/Invoke-E2EOnboardingTest.ps1`) |
| `Documentation/` | Official TAK 5.7 and Federation Hub PDFs |
| `Invoke-TAKOnboarding.ps1` | Root-level — zero-to-team onboarding (certs → users → data packages) |
| `Deploy-TAKServer.ps1` | Root-level — end-to-end deployment orchestration (Phases 0–8) |

Each module follows the same layout:

```
<Module>/
├── <Module>.psd1          ← manifest (FunctionsToExport must be kept in sync)
├── <Module>.psm1          ← loads Private then Public via dot-source
├── Private/               ← internal helpers — never exported
└── Public/                ← one file per exported cmdlet
└── Tests/                 ← Pester 5 unit tests
```

---

## Build & Test Commands

```powershell
# Run tests (prefer single-file to avoid memory pressure)
Invoke-Pester -Path .\TAKServerPS\Tests\TAKServerPS.Module.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\TAKInstall\Tests\TAKInstall.Module.Tests.ps1  -Output Detailed
Invoke-Pester -Path .\TAKDeploy\Tests\TAKDeploy.Module.Tests.ps1    -Output Detailed

# Run all tests for one module
Invoke-Pester -Path .\TAKServerPS\Tests\ -Output Detailed
Invoke-Pester -Path .\TAKInstall\Tests\  -Output Detailed
Invoke-Pester -Path .\TAKDeploy\Tests\   -Output Detailed

# Lint (PSScriptAnalyzer)
Invoke-ScriptAnalyzer -Path .\TAKServerPS\ -Settings .\TAKServerPS\PSScriptAnalyzerSettings.psd1 -Recurse
Invoke-ScriptAnalyzer -Path .\TAKInstall\  -Recurse
Invoke-ScriptAnalyzer -Path .\TAKDeploy\   -Settings .\TAKDeploy\PSScriptAnalyzerSettings.psd1 -Recurse

```

Full test results: [TEST-REPORT.md](../reports/TEST-REPORT.md)

---

## PowerShell Conventions

- **Minimum version:** `#Requires -Version 7.0` in every script/module.
- **Naming:** `Verb-TAKNoun` (e.g. `Get-TAKUser`). Use only [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands).
- **Anatomy of every public cmdlet:**
  1. Full comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, all `.PARAMETER` blocks, at least two `.EXAMPLE` blocks).
  2. `[CmdletBinding()]` + `[OutputType([TypeName])]`.
  3. Typed, validated parameters — `[ValidateNotNullOrEmpty()]`, `[ValidateRange()]`, etc.
  4. `ShouldProcess` on any `New-*`, `Remove-*`, `Set-*`, `Update-*` function. Never on `Get-*`.
  5. Passwords / secrets always as `[SecureString]` — never plain `[string]`.
  6. Errors terminate via `$PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(...))`.
- **Private helpers** (e.g. `Invoke-TAKRequest`, `Invoke-TAKRemoteCommand`) live in `Private/` and are dot-sourced before `Public/` in the `.psm1`.
- **Module session state** in `TAKServerPS` lives in `$script:TAKSession` — all public cmdlets read it; never pass it as a parameter.
- **Linting:** `TAKServerPS` excludes `PSUseBOMForUnicodeEncodedFile` (PS 7 does not require UTF-8 BOM). See [TAKServerPS/PSScriptAnalyzerSettings.psd1](../TAKServerPS/PSScriptAnalyzerSettings.psd1).

### Adding a new cmdlet

1. Create `Public/<Verb>-TAK<Noun>.ps1` (the `.psm1` auto-sources it).
2. Add the function name to `FunctionsToExport` in `<Module>.psd1`.
3. Update the matching count assertion in `<Module>.Module.Tests.ps1`.
4. Add Pester tests for the new function.

---

## Testing Conventions

- **Framework:** Pester 5 — `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }` at the top of every test file.
- **Mocking:** All external calls (`Invoke-RestMethod`, `Invoke-SSHCommand`, etc.) are Mocked. No live TAK Server or SSH host is required.
- **Structure:** `BeforeAll` for setup, `Describe` / `Context` / `It` nesting. Mock objects use `[PSCustomObject]@{...}`.
- **Always run a single file** during development to avoid PowerShell memory pressure; only run the full suite for final validation.

---

## Bash Script Conventions

- All scripts target **Rocky Linux 9** with `#!/usr/bin/env bash`.
- Helper functions live in `utils.sh`; all other scripts source it.
- Scripts are idempotent where possible (check before creating).
- Execution order matters — see [README § Execution Order](../README.md).

---

## Known Limitations

| # | Area | Description |
|---|------|-------------|
| 1 | `Set-TAKUserGroup` | Returns HTTP 500 on TAK Server 5.7-RELEASE8 — `ESAPI.properties` missing from RPM. **Workaround:** `sudo java -jar /opt/tak/utils/UserManager.jar usermod -g GROUP USER` over SSH. |
| 2 | SFTP cert permissions | Certs generated by `makeCert.sh` are `tak:tak` mode 600. SSH user cannot SFTP-download them until `sudo chmod 755 <dir> && sudo chmod 644 <dir>/*` is run. `Invoke-TAKOnboarding.ps1` does this automatically. |
| 3 | `.p12` file path | Client certs live at `/opt/tak/certs/files/<name>.p12` — **not** `/opt/tak/certs/<name>.p12`. Team staging: `/opt/tak/certs/files/teams/<teamname>/`. |
| 4 | TAKInstall linting | `TAKInstall` has no `PSScriptAnalyzerSettings.psd1`, so `PSUseBOMForUnicodeEncodedFile` warnings fire in CI. Do not suppress them with inline `#Suppress` — fix by adding a settings file if needed. |

---

## Security Notes

- Self-signed certs are the norm; `Connect-TAKServer` defaults to `-SkipCertificateCheck $true`. Only set `$false` when using a trusted cert (e.g. Let's Encrypt).
- Never log or hard-code `SecureString` / `PSCredential` values.
- TAK cert files (`.p12`, `.pem`, `.jks`) are secrets — do not commit them.

---

## Key References

- [README.md](../README.md) — full cmdlet tables, network ports, usage examples
- [TEST-REPORT.md](../reports/TEST-REPORT.md) — Pester unit test results (179/179)
- [E2E-ONBOARDING-REPORT.md](../reports/E2E-ONBOARDING-REPORT.md) — Live E2E results (39/46 pass; 7 GroupAssign failures due to ESAPI bug)
- TAK Server 5.7 docs: `Documentation/TAK_Server_Configuration_Guide_5.7.pdf`
- [tak.gov](https://tak.gov) — RPM + GPG key download
- [Posh-SSH](https://github.com/darkoperator/Posh-SSH) — SSH dependency for TAKInstall
