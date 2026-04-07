# Contributing to DigitalTAK

Thank you for contributing. This document explains the branching strategy, development workflow, and CI requirements so that contributors — including forks — can work with the repo confidently.

---

## Branching Strategy

```
prod  ←── dev  ←── feature/your-feature
            ↑
            └── hotfix/critical-fix  (targets prod directly, rare)
```

| Branch | Purpose | Who pushes directly |
|--------|---------|---------------------|
| `prod` | Production-stable. Tagged releases cut from here. | Nobody — merge via PR from `dev` only |
| `dev` | Integration branch. All feature work merges here first. | Owners only for minor fixes; everyone else via PR |
| `feature/*` | Individual features or fixes. Branch from `dev`. | Author |
| `hotfix/*` | Critical production fixes only. Branch from `prod`, PR back to both `prod` and `dev`. | Author |

### Rules

- **Never push directly to `prod`** — open a PR from `dev` (or `hotfix/*`).
- **CI must be green** on the source branch before merging to `dev` or `prod`.
- **One approval required** before merging to `prod` (enforced by branch protection).

---

## Development Setup

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| PowerShell | 7.0+ | [Microsoft Docs](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Pester | 5.x | `Install-Module Pester -Scope CurrentUser` |
| Posh-SSH | any | `Install-Module Posh-SSH -Scope CurrentUser` |
| PSScriptAnalyzer | any | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| ShellCheck | any | `sudo apt install shellcheck` or [shellcheck.net](https://www.shellcheck.net) |

### Running tests locally

```powershell
# All unit tests
.\Invoke-UnitTests.ps1

# Integration tests against a live VM
$env:TAK_INTEGRATION_HOST = '192.168.1.50'
$env:TAK_SSH_PASS         = 'your-ssh-password'
$env:TAK_CERT_PASS        = 'your-cert-password'
.\Invoke-IntegrationTests.ps1

# E2E tests against a live VM
.\Invoke-E2ETests.ps1
```

---

## CI Overview

The CI pipeline (`.github/workflows/ci.yml`) runs automatically on push/PR to `prod`, `dev`, and `main`.

| Job | Runs on | Gate |
|-----|---------|------|
| Pester Tests | ubuntu-latest | Unit + dry-run integration tests |
| PSScriptAnalyzer | ubuntu-latest | PowerShell lint (needs: Pester) |
| ShellCheck | ubuntu-latest | Bash lint (needs: PSScriptAnalyzer) |
| Live-VM Integration | self-hosted tak-vm | Full suite against real VM (manual / release only) |

All standard jobs (top three) run without secrets and pass for any fork with no additional setup. The live-VM job requires `TAK_SSH_PASS` and `TAK_CERT_PASS` repository secrets and a self-hosted runner — forks will naturally skip it.

---

## Forking

1. Fork the repository and clone locally.
2. Create a `dev` branch in your fork: `git checkout -b dev`.
3. All standard CI jobs will pass without any secrets.
4. To run live-VM tests, add `TAK_SSH_PASS` and `TAK_CERT_PASS` as repository secrets in your fork and configure a self-hosted runner with the `tak-vm` label.
5. Open PRs from your fork's feature branch → your fork's `dev` → upstream `dev`.

---

## Release Process

1. Merge `dev` → `prod` via PR (all checks green, one approval).
2. Update `CHANGELOG.md` with the new version section.
3. Push a version tag from `prod`: `git tag v1.2.3 && git push origin v1.2.3`.
4. The `release.yml` workflow creates a GitHub Release automatically, extracting notes from `CHANGELOG.md`.

---

## Commit Style

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

Common types: `feat`, `fix`, `docs`, `ci`, `refactor`, `test`, `chore`.

Examples:
```
feat(TAKInstall): add Update-TAKLetsEncryptCertificate cmdlet
fix(tests): repair stale Deploy-CivTAK.ps1 references in 06-CertPasswordFlow
docs: update operator runbook with live deployment validation findings
ci: add dev branch trigger and concurrency groups
```
