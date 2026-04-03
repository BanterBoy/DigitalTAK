# DigitalTAK Unit Test Summary

**Run date:** 2026-04-02 15:05:08
**Overall status:** PASS
**Duration:** 8.01s

## Results

| Result  | Count |
|---------|-------|
| Passed  | 52 |
| Failed  | 0 |
| Skipped | 0 |
| Total   | 52 |

## Test Paths

- `C:\Users\LukeLeigh\DigitalTAK\TAKDeploy\Tests`

## How to Run Locally

```powershell
# Run all unit tests
.\Invoke-UnitTests.ps1

# Run only TAKDeploy tests
.\Invoke-UnitTests.ps1 -Modules TAKDeploy

# With NUnit XML output
.\Invoke-UnitTests.ps1 -OutputPath reports\TestResults-Unit.xml
```

## Prerequisites

- PowerShell 7.0+
- Pester 5.0+: `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force`
- Hyper-V module (for TAKDeploy import): Windows host with Hyper-V role enabled, or Hyper-V RSAT tools

> **Note:** No live TAK Server, Hyper-V VM, or SSH session is required. All external
> dependencies are mocked inside the test files.

## Next Test Priorities

1. **Integration tests** — validate the full deployment pipeline against a live Hyper-V VM (see `tests/integration/`)
2. **TAKInstall module** — unit tests for Install-TAKServer, New-TAKServerCertificate, etc.
3. **TAKServerPS module** — unit tests for REST API user management cmdlets
4. **Edge cases** — error paths in Assert-HyperVPrerequisites (missing modules, non-admin, missing ISO/RPM)
5. **Negative path coverage** — Wait-TAKLinuxInstall with multiple NIC adapters and manual IP override
