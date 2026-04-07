# Legacy Integration Tests (Archived)

These five test files (`01`–`05`) were the original integration-test suite written before the current `tests/integration/` layout was established.

They are **not executed** as part of the CI pipeline. They are preserved here for historical reference only.

## Superseded by

`tests/integration/` — the current integration-test suite, structured with Pester 5 and executed via `Invoke-Pester`.

## Files

| File | Description |
|------|-------------|
| `01-VMProvisioning.Tests.ps1` | Hyper-V VM creation and network checks |
| `02-OSInstall.Tests.ps1` | Rocky Linux 9 kickstart / cloud-init smoke tests |
| `03-TAKServerHealth.Tests.ps1` | TAK Server service health checks |
| `04-Certificates.Tests.ps1` | CA and client certificate generation checks |
| `05-UserManagement.Tests.ps1` | TAK user / admin promotion checks |
| `Helpers.ps1` | Shared helper functions used by the above tests |

## Migration note

The tests in `tests/integration/` cover the same scenarios with improved isolation,
idempotency checks, and Pester 5 `BeforeAll`/`AfterAll` lifecycle hooks.
