# Changelog

All notable changes to DigitalTAK are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — 2026-04-01

### Fixed
- `Deploy-TAKServer.ps1` (Phase 5): Added port-readiness poll before post-deployment
  port tests. Polls port 8443 for up to 90s after Phase 4 restart so TAK Server's
  Java processes have time to bind — eliminates false-negative test failures on
  every fresh deploy.
- `Deploy-TAKServer.ps1` (Phase 5): Fixed `awk '{print \$2}'` memory-collection
  command where `\$2` was mis-interpreted by PowerShell's string expander; replaced
  with `` awk '/Mem/{print `$2}' `` so `$2` is passed correctly to awk.

### Added
- `.github/workflows/ci.yml`: TAKDeploy Pester tests now run in CI (`TAKDeploy/Tests/`).
  Previously the 32-test TAKDeploy suite ran outside CI.
- `.github/workflows/ci.yml`: PSScriptAnalyzer now lints `TAKDeploy/` and the two
  root orchestration scripts (`Deploy-TAKServer.ps1`, `Deploy-TAKTestServer.ps1`).
- `InstallShellScripts/openfire_takChat_install.sh`: Added `mkdir -p /atakciv`
  before the Openfire RPM download so the script no longer fails if the directory
  is absent. `TXTScripts/openfire_takChat_install.txt` mirror updated to match.

### Changed
- Repository wiki migrated from in-repo `Wiki/` and `Documentation/Wiki/` to the
  GitHub Wiki (`https://github.com/BanterBoy/DigitalTAK/wiki`). In-repo wiki
  directories removed; `README.md` updated to point to the GitHub Wiki.

---

## [1.0.0] — 2026-03-22

### Added (Session 3)
- `TAKServerPS/Private/Invoke-TAKRequest.ps1`: `-RetryCount` (0–5, default 2)
  and `-RetryDelaySeconds` (1–30, default 3) parameters — automatically retries
  on HTTP 429/503 and `HttpRequestException` transient failures.
- `TAKServerPS/Private/Invoke-TAKRequest.ps1`: `-AutoPage` switch —
  automatically pages through all results using TAK's `offset`/`limit` pattern
  and returns a combined array.
- `TAKServerPS/Public/Remove-TAKUser.ps1`: `-AlsoRevokeCertificates` switch —
  revokes all user certificates via `Get-TAKCertificate | Remove-TAKCertificate`
  before deleting the account.
- `TAKServerPS/Tests/Get-TAKVersion.Tests.ps1` — 9 new tests.
- `TAKServerPS/Tests/New-TAKUser.Tests.ps1` — 12 new tests.
- `TAKServerPS/Tests/Remove-TAKUser.Tests.ps1` — 10 new tests.
- `TAKServerPS/Tests/Invoke-TAKCertificateSign.Tests.ps1` — 11 new tests.
- Retry and AutoPage tests appended to `Invoke-TAKRequest.Tests.ps1` — 14 new
  tests. Total test count: **160** (TAKServerPS) + TAKInstall, 0 failures.
- `Documentation/channels-README.md` — documents `channels.zip`, ATAK channel
  configuration, and client deployment steps.

### Changed (Session 3)
- `InstallShellScripts/RL9_tak5.7r8_install.sh`:
  - Added `utils.sh` copy step (`cp` + `chmod 755`) to `/opt/tak/certs/` so
    `createTakCerts.sh` can source it after TAK Server installation.
  - `vim` installation now opt-in via `INSTALL_VIM=true` environment variable
    (was unconditionally installed).
- `InstallShellScripts/promoteAdmin.sh`:
  - Added `set -euo pipefail`.
  - Added `id atak` guard — exits with an error if the `atak` OS user does not
    exist before attempting to promote.
  - `/home/atak` created with `mkdir -p` if absent.
  - `admin.p12` copied with `chown atak:atak` and `chmod 640` instead of
    world-readable permissions.
- `InstallShellScripts/takserver_createLECerts.sh`:
  - `printf '%q'` replaced with `sed_replace_quote()` for `CERT_NAME` and
    `CERT_PASSWORD` when writing `/etc/takserver_renew.conf`
    (`%q` is bash-only and not available in all POSIX shells).
  - Added `SECURITY NOTE` comment on `/etc/takserver_renew.conf` recommending
    `systemd-creds` or a secrets vault for production.

### Removed (Session 3)
- `TAKserverAPI/takVersion-5.6-RELEASE-14-openapispec.json` — stale TAK 5.6
  OpenAPI spec removed; TAK 5.7 REST API is documented in the TAK Configuration
  Guide PDF.

### Added (Session 1 & 2)
- `TAKServerPS` module — 44 cmdlets covering the full TAK Server 5.7 REST API
  (users, groups, missions, certs, inputs, data feeds, video, federation, CoT).
- `TAKInstall` module — 6 cmdlets for remote provisioning of TAK Server 5.7 on
  Rocky Linux 9 via SSH (Posh-SSH dependency).
- Pester test suite — 179 tests across 7 test files (zero mocked live calls,
  all passing).
- `InstallShellScripts/utils.sh` — shared Bash helper library with
  `bash_quote()`, `sed_replace_quote()`, and `wait_for_service()`.
- `Sync-TXTMirrors.ps1` — repo-root script to sync `TXTScripts/` from
  `InstallShellScripts/` sources.
- `.github/workflows/ci.yml` — GitHub Actions CI:
  Pester + PSScriptAnalyzer + ShellCheck + TXT mirror sync check.

### Changed (Session 1 & 2)
- `TAKServerPS` module — 44 cmdlets covering the full TAK Server 5.7 REST API
  (users, groups, missions, certs, inputs, data feeds, video, federation, CoT).
- `TAKInstall` module — 6 cmdlets for remote provisioning of TAK Server 5.7 on
  Rocky Linux 9 via SSH (Posh-SSH dependency).
- Pester test suite — 179 tests across 7 test files (zero mocked live calls,
  all passing).
- `InstallShellScripts/utils.sh` — shared Bash helper library with
  `bash_quote()`, `sed_replace_quote()`, and `wait_for_service()`.
- `Sync-TXTMirrors.ps1` — repo-root script to sync `TXTScripts/` from
  `InstallShellScripts/` sources.
- `.github/workflows/ci.yml` — GitHub Actions CI:
  Pester + PSScriptAnalyzer + ShellCheck + TXT mirror sync check.

### Changed
- `createTakCerts.sh`:
  - Password escaping replaced with `sed_replace_quote()` from `utils.sh`
    (fixes silent corruption for passwords containing `\`, `$`, or `` ` ``).
  - 360-second sleep countdowns replaced with `wait_for_service takserver`
    polling (saves 5–7 minutes per deployment).
  - Added `grep -q` validation after every `sed -i` patch to cert-metadata.sh.
  - Added root CA name prompt; value passed to
    `takUserCreateCerts_doNotRunAsRoot.sh` via `TAK_CA_NAME` env variable.
  - Added UPPERCASE+digits-only input validation for all cert metadata fields.
  - Removed stale progress-bar `echo "70"` / `sleep 10s` dead code from header.
- `takserver_createLECerts.sh`:
  - Replaces weak `sed 's/[&|]/\\&/g'` password escape with `sed_replace_quote()`
    (fixes silent corruption for passwords containing `\` or `"`).
  - Added validation after CoreConfig.xml 8446-connector `sed -i` patch.
  - Sources `utils.sh` via `SCRIPT_DIR`-relative path.
- `takUserCreateCerts_doNotRunAsRoot.sh`:
  - Added `TAK_CA_NAME` environment-variable passthrough to eliminate
    the interactive `makeRootCa.sh` prompt when called from `createTakCerts.sh`.
  - Falls back to interactive mode if `TAK_CA_NAME` is unset.
  - Added `set -euo pipefail`.
- `openfire_takChat_install.sh`:
  - `curl -L` changed to `curl -fL` (fail-fast on HTTP errors).
  - Added `OPENFIRE_RPM_SHA256` variable and `sha256sum --check` verification.
  - Updated stale script reference in header comment.
- `TAKInstall/Public/Install-TAKServer.ps1`:
  - Remote work directory created with `chmod 700` (was `chmod 777`).
  - Added `utils.sh` to the cert-script SCP/copy step so `createTakCerts.sh`
    can source it from `/opt/tak/certs/`.
- `TAKServerPS/Public/Connect-TAKServer.ps1`:
  - Connectivity test endpoint changed from `/Marti/api/ver` to
    `/Marti/api/version/info` (canonical TAK 5.7 path).
- Both module manifests:
  - `ProjectUri` corrected to `https://github.com/BanterBoy/DigitalTAK`.
  - `ReleaseNotes` added for v1.0.0.

### Security
- Passwords with special characters (`\`, `$`, `` ` ``, `"`) no longer silently
  corrupt `CoreConfig.xml`.
- Openfire RPM download is now fail-fast; SHA-256 checksum guard available via
  `OPENFIRE_RPM_SHA256` environment variable.
- Remote staging directory tightened from world-writable (777) to owner-only
  (700).

---

## Prior to 1.0.0

- March 2025: Rocky Linux 9 confirmed as target OS; CentOS not supported.
- March 2025: Hyper-V Gen 2 deployment with External vSwitch.
- March 2025: TAK 5.7-RELEASE8 targeted.
- March 2025: Install script renamed
  `RL9.5_tak5.4r14_install.sh` → `RL9_tak5.7r8_install.sh`.
- March 2025: Stale TAK 5.6 PDF and OpenAPI spec removed; README rewritten.
