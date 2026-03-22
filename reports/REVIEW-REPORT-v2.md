# DigitalTAK Comprehensive Review Report — v2

**Reviewed:** 2026-03-22 (Session 2) | **Reviewer:** GitHub Copilot (DigitalTAK Orchestrator mode)  
**Previous Report:** [reports/REVIEW-REPORT-v1.md](reports/REVIEW-REPORT-v1.md)  
**Coverage:** 8 Bash scripts · 44 TAKServerPS cmdlets · 6 TAKInstall cmdlets · 7 Pester test files · CI workflow · manifests · CHANGELOG

---

## 1. Executive Summary

This report reviews the DigitalTAK codebase after a full implementation pass that resolved all 10 recommendations from the v1 report. The project has made substantial progress: the shared `utils.sh` Bash library eliminates duplicate escape logic, `wait_for_service()` saves 5–7 minutes per deployment, all cert-metadata patches now validate, the Openfire installer is hardened against supply-chain attack, and a four-job CI pipeline now enforces quality gates on every push.

One **new critical issue** was introduced during the action plan: `RL9_tak5.7r8_install.sh` does not copy `utils.sh` to `/opt/tak/certs/` before calling `createTakCerts.sh`. The latter sources `utils.sh` at launch, so Bash-only deployments will crash immediately with _"utils.sh: No such file or directory"_. The PowerShell path (`Install-TAKServer.ps1`) already copies `utils.sh` correctly and is unaffected.

A second issue — bash-quoting contamination (`'"'"'`) injected into the PowerShell manifest `TAKInstall.psd1` as `ReleaseNotes` — was **found and fixed in this session**. Tests are fully green: **179/179 passing, 0 failed**.

| Category | v1 Score | v2 Score | Change |
|---|---|---|---|
| 🏗️ **Architecture** | 8.5 | 8.5 | — |
| 💻 **Code Quality** | 8.0 | 8.5 | ▲ 0.5 |
| 🔒 **Security** | 6.5 | 7.5 | ▲ 1.0 |
| 🔧 **Maintainability** | 7.0 | 8.5 | ▲ 1.5 |
| 🎯 **UX / DX** | 8.0 | 8.5 | ▲ 0.5 |

---

## 2. Change Log Since v1

### Items Completed (all 10 from v1 action plan)

| # | Item | Status |
|---|---|---|
| 1 | Create `utils.sh` shared library (`bash_quote`, `sed_replace_quote`, `wait_for_service`) | ✅ Done |
| 2 | Rewrite `createTakCerts.sh`: escaping, service waits, cert-metadata validation, CA name passthrough | ✅ Done |
| 3 | Update `takserver_createLECerts.sh`: source `utils.sh`, `sed_replace_quote`, CoreConfig validation | ✅ Done |
| 4 | Update `takUserCreateCerts_doNotRunAsRoot.sh`: `TAK_CA_NAME` env passthrough, `set -euo pipefail` | ✅ Done |
| 5 | Harden `openfire_takChat_install.sh`: `curl -fL`, `sha256sum --check` | ✅ Done |
| 6 | Fix `Install-TAKServer.ps1`: `chmod 700` (was 777), copy `utils.sh` to `/opt/tak/certs/` | ✅ Done |
| 7 | Fix `Connect-TAKServer.ps1`: connectivity probe endpoint → `/Marti/api/version/info` | ✅ Done |
| 8 | Create `Sync-TXTMirrors.ps1`; sync all 8 TXT mirrors | ✅ Done |
| 9 | Create `.github/workflows/ci.yml` (pester, psscriptanalyzer, shellcheck, txt-sync) | ✅ Done |
| 10 | Update both manifests (`ProjectUri`, `ReleaseNotes`), create `CHANGELOG.md`, move `ORCHESTRATOR.md` to `.github/agents/`, remove stale files | ✅ Done |

### New Issues Found in This Session

| # | Issue | Severity | Status |
|---|---|---|---|
| N1 | `RL9_tak5.7r8_install.sh` does not copy `utils.sh` → `createTakCerts.sh` crashes on Bash-path deploys | 🔴 Critical | ❌ Open |
| N2 | `TAKInstall.psd1` `ReleaseNotes` contained bash-quoting `'"'"'` (invalid PowerShell syntax) | 🔴 Critical | ✅ Fixed this session |

---

## 3. Current State — All Files

### `InstallShellScripts/utils.sh` *(new, created session 1)*

Shared library sourced by `createTakCerts.sh` and `takserver_createLECerts.sh`. Contains:

- **`bash_quote()`** — `${1//\'/\'\\\'\'}` wraps input in single quotes; correctly handles any embedded `'`
- **`sed_replace_quote()`** — escapes `\`, `|`, and `&` for sed replacement context. Intentionally does **not** escape `$` or `` ` `` (correct — sed replaces string-literally in replacement fields, not shell-expanded)
- **`wait_for_service SERVICE [TIMEOUT]`** — polls `systemctl is-active` with a 10-second interval; prints progress every poll; exits 1 on timeout

State: **clean and correct**.

### `InstallShellScripts/createTakCerts.sh` *(rewritten session 1)*

All v1 issues resolved:

- `source "$SCRIPT_DIR/utils.sh"` — shared library loaded ✅
- Input validation: `^[A-Z0-9]+$` regex on all four cert-metadata fields ✅
- CA name prompt with `TAK_CA_NAME` env export for passthrough to child script ✅
- `sudo -u tak -E` (environment-preserving) so `TAK_CA_NAME` reaches `takUserCreateCerts_doNotRunAsRoot.sh` ✅
- `escapedTakCertPass="$(sed_replace_quote "$takCertPass")"` replacing broken multi-pass sed escape ✅
- `wait_for_service takserver 180` / `wait_for_service takserver 300` replacing 360 seconds of hardcoded sleep ✅
- Four `grep -q` post-patch validations after each `sed -i` to cert-metadata.sh ✅
- `grep -q 'auth="x509"'`, `grep -q 'truststore-intermediate-ca.jks'`, `grep -q 'keystorePass='` validations on CoreConfig.xml ✅

**Remaining gap:** `source "$SCRIPT_DIR/utils.sh"` at runtime uses `SCRIPT_DIR=/opt/tak/certs/`, but `utils.sh` is not placed there by `RL9_tak5.7r8_install.sh`. **This script will crash on Bash-path deployments.** See Critical Issue N1.

### `InstallShellScripts/takUserCreateCerts_doNotRunAsRoot.sh` *(updated session 1)*

- `set -euo pipefail` ✅
- `TAK_CA_NAME` passthrough: `if [ -n "${TAK_CA_NAME:-}" ]; then echo "$TAK_CA_NAME" | ./makeRootCa.sh; else ./makeRootCa.sh; fi` ✅

### `InstallShellScripts/takserver_createLECerts.sh` *(updated session 1)*

- `source "$SCRIPT_DIR/utils.sh"` ✅
- `escapedCertPassword="$(sed_replace_quote "$certPassword")"` ✅
- `grep -q 'keystorePass='` CoreConfig validation ✅

**Remaining gap:** `printf 'CERT_PASSWORD=%q\n'` when writing `/etc/takserver_renew.conf`. The `%q` format specifier is a bashism, not POSIX — its quoting output varies between bash 4.x and 5.x and is not safe for all password contents. This was identified in v1 and deferred; it remains open (see Medium issue M1).

### `InstallShellScripts/openfire_takChat_install.sh` *(updated session 1)*

- `curl -fL` (fail on HTTP errors) ✅
- `OPENFIRE_RPM_SHA256` environment guard: if unset, skips checksum with a warning ✅
- `sha256sum --check` when SHA256 is provided ✅
- Header comment updated to reference `RL9_tak5.7r8_install.sh` ✅

### `InstallShellScripts/RL9_tak5.7r8_install.sh` *(not updated in session 1)*

**Critical gap (N1):** The script copies only:
```bash
sudo cp "$SCRIPT_DIR/createTakCerts.sh" /opt/tak/certs
sudo cp "$SCRIPT_DIR/takUserCreateCerts_doNotRunAsRoot.sh" /opt/tak/certs
```
It does **not** copy `utils.sh`. When the operator runs `createTakCerts.sh` from `/opt/tak/certs/`, the script immediately fails:
```
/opt/tak/certs/createTakCerts.sh: line 15: /opt/tak/certs/utils.sh: No such file or directory
```

**Fix required:**
```bash
sudo cp "$SCRIPT_DIR/utils.sh" /opt/tak/certs
sudo chmod 755 /opt/tak/certs/utils.sh
```

Other noted items (unchanged from v1, not yet actionable):
- `vim` installed unconditionally (low priority; no `INSTALL_VIM` guard)

### `InstallShellScripts/promoteAdmin.sh` *(not touched in session 1)*

Still missing all three hardening items from v1:

- No `set -euo pipefail` ❌
- No `id atak` check before assuming user exists ❌
- Hard-coded `cp /opt/tak/certs/files/admin.p12 /home/atak/` — no `mkdir -p /home/atak` guard ❌
- No `chmod 640 /home/atak/admin.p12` (the PowerShell `Set-TAKAdminCertificate` already applies this; the Bash equivalent is weaker) ❌

### `InstallShellScripts/takserver_renewLECerts.sh` *(not touched in session 1)*

Sources the `/etc/takserver_renew.conf` config written by `takserver_createLECerts.sh`. The `%q` renewal config risk applies here too (see M1).

---

### `TAKInstall/Public/Install-TAKServer.ps1` *(updated session 1)*

Key changes verified:
- Step 5: `chmod 700 $RemoteWorkDir` (was `chmod 777`) ✅
- Step 11: `sudo cp $RemoteWorkDir/utils.sh /opt/tak/certs/ 2>/dev/null || true` ✅

PowerShell-provisioned deployments are therefore **not** affected by the `utils.sh` gap — only pure Bash deployments are at risk.

### `TAKServerPS/Public/Connect-TAKServer.ps1` *(updated session 1)*

Connectivity probe: `/Marti/api/version/info` (was `/Marti/api/ver`) ✅

### `TAKInstall/TAKInstall.psd1` *(bug introduced session 1, fixed session 2)*

**Bug introduced in session 1:** `ReleaseNotes` value contained bash-style single-quote embedding:
```
'...and Let'"'"'s Encrypt.'
```
This is valid shell but invalid PowerShell, causing `Test-ModuleManifest` (and `Import-Module`) to throw a parse error. All 10 TAKInstall tests that depend on the manifest failed.

**Fixed in this session:** Replaced with `'...and LetsEncrypt.'` — apostrophe removed from `Let's`. ✅

### `TAKServerPS/TAKServer.psd1` *(updated session 1)*

- `ProjectUri = 'https://github.com/BanterBoy/DigitalTAK'` ✅
- `ReleaseNotes = 'v1.0.0 — Initial release...'` (em-dash `—` is valid in PowerShell strings) ✅

### `.github/workflows/ci.yml` *(new, created session 1)*

Four jobs on push/PR to `prod`/`main`:
- **pester** — runs both test suites on Ubuntu with PowerShell 7.4 and 7.5
- **psscriptanalyzer** — lints both modules; exits non-zero on any finding
- **shellcheck** — lints all `InstallShellScripts/` bash files
- **txt-sync** — diffs every `.sh` against its `.txt` mirror; fails if any are out of sync

### `Sync-TXTMirrors.ps1` *(new, created session 1)*

`[CmdletBinding(SupportsShouldProcess)]` — iterates `InstallShellScripts/*.sh`, copies to `TXTScripts/*.txt`. All 8 mirrors (including `utils.txt`) confirmed in sync.

### `CHANGELOG.md` *(new, created session 1)*

Full v1.0.0 entry documenting all changes. ✅

### `TAKserverAPI/openapispec.json` *(renamed session 1, content not updated)*

The file was renamed from `takVersion-5.6-RELEASE-14-openapispec.json` to `openapispec.json`. The content is still the TAK 5.6 OpenAPI specification. For a 5.7-targeting repository, this should either be updated to the 5.7 spec or removed. (Low priority — the spec is not referenced by any script.)

---

## 4. Test Suite — Current State

**179 tests passing, 0 failing** across 7 test files.

| File | Tests | Passed | Failed |
|---|---|---|---|
| TAKServerPS.Module.Tests.ps1 | 73 | 73 | 0 |
| Connect-TAKServer.Tests.ps1 | 19 | 19 | 0 |
| Invoke-TAKRequest.Tests.ps1 | 22 | 22 | 0 |
| **TAKServerPS subtotal** | **114** | **114** | **0** |
| TAKInstall.Module.Tests.ps1 | 31 | 31 | 0 |
| Wait-TAKServiceReady.Tests.ps1 | 14 | 14 | 0 |
| Invoke-TAKRemoteCommand.Tests.ps1 | 16 | 16 | 0 |
| ConvertTo-TAKBashArg.Tests.ps1 | 13 | 13 | 0 |
| **TAKInstall subtotal** | **65** | **65** | **0** |
| **Grand total** | **179** | **179** | **0** |

**Infrastructure:** PowerShell 7.6.0 · Pester 5.7.1 · PSScriptAnalyzer 1.24.0 · Posh-SSH (required by TAKInstall)

**Coverage gaps (unchanged from v1):**
- No tests for 43/44 TAKServerPS public cmdlets beyond `Connect-TAKServer`
- No tests for `Install-TAKServer` or `New-TAKServerCertificate` (highest risk cmdlets)
- No `PSScriptAnalyzer` integrated into Pester run (PSA is separate in CI)
- No negative tests for out-of-range port values, malformed hostnames, etc.

---

## 5. Open Issues — Prioritized

---

### 🔴 Critical — Must Fix Before Any Bash-Path Deployment

---

#### N1 — `RL9_tak5.7r8_install.sh` does not copy `utils.sh`

**Component:** `InstallShellScripts/RL9_tak5.7r8_install.sh`  
**Impact:** Runtime crash on every Bash-path deployment  
**Effort:** Trivial (2 lines)

`createTakCerts.sh` line 15: `source "$SCRIPT_DIR/utils.sh"`. When `createTakCerts.sh` runs from `/opt/tak/certs/`, it needs `utils.sh` in the same directory. `RL9_tak5.7r8_install.sh` copies two scripts to that directory but not `utils.sh`.

**Fix:**
```bash
# Add after the existing cp commands (around line where createTakCerts.sh is copied):
sudo cp "$SCRIPT_DIR/utils.sh" /opt/tak/certs
sudo chmod 755 /opt/tak/certs/utils.sh
```

**Also update TXT mirror** and confirm `utils.txt` is kept in sync.

---

### 🟠 High Priority

---

#### H1 — `promoteAdmin.sh` missing all safety guards

**Component:** `InstallShellScripts/promoteAdmin.sh`  
**Impact:** Silent failure or permission errors on non-default systems  
**Effort:** Low

```bash
# Add at top of script:
set -euo pipefail

# Guard user existence:
if ! id atak &>/dev/null; then
    echo "ERROR: User 'atak' does not exist. Run the TAK installer first."
    exit 1
fi

# Guard home directory:
sudo mkdir -p /home/atak
sudo chown atak:atak /home/atak

# After cp:
sudo chown atak:atak /home/atak/admin.p12
sudo chmod 640 /home/atak/admin.p12
```

Note: `Set-TAKAdminCertificate.ps1` already applies `chmod 640` and `chown atak:atak`. The Bash script is currently weaker than its PowerShell counterpart.

---

#### H2 — No retry logic in `Invoke-TAKRequest`

**Component:** `TAKServerPS/Private/Invoke-TAKRequest.ps1`  
**Impact:** Any transient 429/503/network blip aborts long batch operations  
**Effort:** Medium (no breaking change)  

Add `-RetryCount [int]` and `-RetryDelaySeconds [int]` parameters with a do/while retry loop around `Invoke-RestMethod`. Default `RetryCount = 2`, `RetryDelaySeconds = 3`.

---

#### H3 — No pagination support in `Invoke-TAKRequest`

**Component:** `TAKServerPS/Private/Invoke-TAKRequest.ps1`  
**Impact:** List endpoints silently return only the first page (TAK servers with 500+ users return partial results)  
**Effort:** Medium  

Add an `-AutoPage` switch that follows TAK's `offset`/`limit` pagination pattern until the response set is exhausted.

---

### 🟡 Medium Priority

---

#### M1 — `printf '%q'` in `takserver_createLECerts.sh` and renewal config

**Component:** `InstallShellScripts/takserver_createLECerts.sh`  
**Impact:** Non-POSIX quoting — `%q` behaviour varies across bash versions; passwords with unusual characters may be misformatted in `/etc/takserver_renew.conf`  
**Effort:** Low

Replace `printf 'CERT_PASSWORD=%q\n' "$certPassword"` with:
```bash
printf 'CERT_PASSWORD=%s\n' "$(sed_replace_quote "$certPassword")"
```
Or use `bash_quote` and validate that the renewal script can consume the format.

Also consider adding a `SECURITY NOTE` comment near the `/etc/takserver_renew.conf` write explaining the plaintext risk for production deployments.

---

#### M2 — `TAKserverAPI/openapispec.json` contains stale 5.6 spec

**Component:** `TAKserverAPI/`  
**Impact:** Misleading reference material — the repo targets 5.7  
**Effort:** Low

Either replace with the TAK 5.7 OpenAPI spec or remove the directory entirely. No script in the repo references it.

---

#### M3 — No tests for 43/44 public TAKServerPS cmdlets

**Component:** `TAKServerPS/Tests/`  
**Impact:** Regressions in `Remove-TAKUser`, `Get-TAKMission`, etc. are undetected  
**Effort:** Medium–High  

Priority additions from highest-risk cmdlets:
- `Invoke-TAKCertificateSign.Tests.ps1`
- `New-TAKUser.Tests.ps1` (plaintext password in memory risk)
- `Remove-TAKUser.Tests.ps1`
- `Get-TAKVersion.Tests.ps1` (the `.data` unwrap ambiguity at a no-data endpoint)

---

### 🟢 Low / Polish

---

#### L1 — `RL9_tak5.7r8_install.sh` installs `vim` unconditionally

```bash
# Current:
sudo dnf install -y vim
# Should be:
INSTALL_VIM="${INSTALL_VIM:-false}"
[ "$INSTALL_VIM" = "true" ] && sudo dnf install -y vim || true
```

#### L2 — No `Remove-TAKUser -AlsoRevokeCertificates` switch

Convenience wrapper that chains `Get-TAKCertificate | Remove-TAKCertificate` before deleting the user. Identified in v1; still open.

#### L3 — `channels.zip` is undocumented

The channels archive is present in the repo root with no explanation of its structure, how to update it, or how to replace it for a new unit/organisation. A `Documentation/channels-README.md` would close this gap.

#### L4 — Both modules at `1.0.0` with no matching git tag

Establish a `v1.0.0` git tag or switch to `0.x.x` pre-release versioning before any external distribution.

---

## 6. Architecture Assessment

### What improved

- **Bash shared library** (`utils.sh`): eliminates two competing escape implementations. All password-touching `sed` commands in `createTakCerts.sh` and `takserver_createLECerts.sh` now route through `sed_replace_quote()`.
- **Service readiness**: `wait_for_service()` replaces 360 seconds of unconditional sleep. Combined with the PowerShell `Wait-TAKServiceReady` counterpart, service-wait is now correct across both deployment paths.
- **CI gates**: The four-job workflow catches manifest parse errors, PSA violations, ShellCheck findings, and TXT mirror drift automatically on every push.
- **Posh-SSH typing**: All `Invoke-TAKRemoteCommand` and `Wait-TAKServiceReady` usages already pass `[SSH.SshSession]`; this is enforced and tested.

### What still lags

- **Bash-path deployment is currently broken** (N1). This is the most urgent item; every Bash-path operator will hit it on the first post-action-plan run.
- **`promoteAdmin.sh`** has no `set -euo pipefail` and no guards — it is qualitatively weaker than every other script in the repo.
- **Bash idempotency** remains zero across all scripts. Acceptable for the current use-case (single fresh-install workflow), but a re-run will either fail or silently corrupt configuration.
- **Test depth** is still confined to module-level, `Connect-TAKServer`, `Invoke-TAKRequest`, and the three TAKInstall private helpers. The 44 public cmdlets are exercised only via manifest/metadata tests.

### Bash ↔ PowerShell parity table

| Feature | Bash | PowerShell | Parity |
|---|---|---|---|
| CA name passthrough | `TAK_CA_NAME` env var via `sudo -u tak -E` | `$CAName` parameter | ✅ |
| Service wait | `wait_for_service()` — stopwatch + polling | `Wait-TAKServiceReady` — same | ✅ |
| Password escaping | `sed_replace_quote()` — `\`, `\|`, `&` only | `ConvertTo-TAKBashArg` — `'\''` pattern | ✅ (both correct for context) |
| Cert metadata validation | `grep -q` after each `sed -i` | SSH grep check after remote sed | ✅ |
| utils.sh present at runtime | ❌ Not copied by bash installer | ✅ Copied by `Install-TAKServer.ps1` | **Bash lags** |
| promoteAdmin hardening | ❌ No guards | ✅ `chmod 640`, `chown` applied | **Bash lags** |
| Idempotency | ❌ None | ❌ None (by design) | Same gap |

---

## 7. Sub-Agent Action Plan

### For `tak-install` sub-agent

Priority 1 (Critical):
- Add `sudo cp "$SCRIPT_DIR/utils.sh" /opt/tak/certs` + `chmod 755` immediately after the existing `cp createTakCerts.sh` line
- Sync `TXTScripts/RL9_tak5.7r8_install.txt` after the edit

Priority 2 (High):
- Add `INSTALL_VIM` guard (L1)

### For `tak-certs` sub-agent

Priority 1 (High):
- Add `set -euo pipefail` to `promoteAdmin.sh`
- Add `id atak` guard and `mkdir -p /home/atak` + `chmod 640` (H1)
- Sync `TXTScripts/promoteAdmin.txt`

Priority 2 (Medium):
- Replace `printf '%q'` in `takserver_createLECerts.sh` with `sed_replace_quote` approach (M1)
- Sync `TXTScripts/takserver_createLECerts.txt`

### For TAKServerPS sub-agent

Priority 1 (High):
- Add retry logic to `Invoke-TAKRequest` — `RetryCount` and `RetryDelaySeconds` parameters (H2)
- Add `AutoPage` switch to `Invoke-TAKRequest` (H3)
- Add `Remove-TAKUser -AlsoRevokeCertificates` (L2)

Priority 2 (Medium):
- Add test files for `Invoke-TAKCertificateSign`, `New-TAKUser`, `Remove-TAKUser`, `Get-TAKVersion` (M3)

### For documentation sub-agent

- Document `channels.zip` structure in `Documentation/channels-README.md` (L3)
- Remove or replace `TAKserverAPI/openapispec.json` with 5.7 content (M2)
- Add `v1.0.0` git tag or switch manifests to `0.x.x` pre-release (L4)

---

## 8. Session-2 Bug Fix Record

### TAKInstall.psd1 — Bash Shell Quoting Contamination

**Root cause:** During session 1, `multi_replace_string_in_file` authored `ReleaseNotes` in `TAKInstall.psd1` using the bash shell idiom `'"'"'` to embed a literal single quote inside a single-quoted string. This pattern is valid for bash heredoc/argument contexts but is **not valid PowerShell syntax** — a `.psd1` file is a PowerShell data structure, not a bash script.

**Symptom:** `Test-ModuleManifest` and `Import-Module` both threw:
```
Unexpected token `'"'"'` in expression or statement.
```
All 10 TAKInstall tests that depend on module import failed.

**Fix applied this session:**
```powershell
# Old (invalid):
'v1.0.0 - Initial release. ...and Let'"'"'s Encrypt.'
# New (valid):
'v1.0.0 - Initial release. ...and LetsEncrypt.'
```
The apostrophe was removed from `Let's` rather than re-encoded, keeping the string simple and avoiding the risk of re-introducing quoting errors.

**Prevention:** When writing arbitrary text into a PowerShell `.psd1` value:
- Single-quoted strings `'...'`: cannot contain `'` at all; the only safe option is to remove apostrophes, use double-quoted strings, or use a here-string.
- Double-quoted strings `"..."`: need `$` and `` ` `` escaped.
- Here-string `@'...'@`: safe for all content.

---

*Report generated after all 179/179 Pester tests confirmed passing. Next review recommended after implementing Critical issue N1 and High-priority items H1–H3.*
