# DigitalTAK — Recommendations Report

**Date:** 2026-03-24  
**Based on:** End-to-End Test Report (same date)  
**Priority:** High / Medium / Low

---

## High Priority

### 1. Add a startup delay before post-deployment port tests

**Problem:** The deployment script's Phase 5 validation tests run immediately after the Phase 4 `systemctl restart takserver`. TAK Server's Java processes need 30-60 seconds to bind ports 8089, 8443, and 8446 after the service reports `active`. This causes 4 false-negative test failures on every fresh deploy.

**Recommendation:** Add a `Wait-TAKServiceReady`-style port-readiness poll before running the Phase 5 port tests. Either:
- Call the existing `Wait-TAKServiceReady` private helper from TAKInstall, or
- Add a simple loop that polls `ss -tlnp | grep 8443` until it returns, with a 60-second timeout.

**Files:** `Deploy-TAKServer.ps1` (Phase 5 section, around line 604)

---

### 2. Add TAKDeploy to CI pipeline

**Problem:** TAKDeploy has 32 Pester tests and a PSScriptAnalyzerSettings file, but CI (`ci.yml`) only runs tests for TAKServerPS and TAKInstall. TAKDeploy changes can ship without automated validation.

**Recommendation:** Add TAKDeploy to both the Pester and PSScriptAnalyzer CI jobs:
```yaml
# Pester job
- name: Run TAKDeploy Tests
  run: |
    Invoke-Pester -Path ./TAKDeploy/Tests/ -CI

# PSScriptAnalyzer job  
- name: Lint TAKDeploy
  run: |
    $results = Invoke-ScriptAnalyzer -Path ./TAKDeploy/ -Settings ./TAKDeploy/PSScriptAnalyzerSettings.psd1 -Recurse
```

**Files:** `.github/workflows/ci.yml`

---

### 3. Create a PSScriptAnalyzerSettings.psd1 for TAKInstall

**Problem:** TAKInstall has no analyzer settings file. CI runs default rules against it, which includes `PSUseBOMForUnicodeEncodedFile` — a rule that fires on UTF-8 files without BOM, which is correct for PowerShell 7+. TAKServerPS already excludes this rule.

**Recommendation:** Copy `TAKServerPS/PSScriptAnalyzerSettings.psd1` to `TAKInstall/PSScriptAnalyzerSettings.psd1` and update CI to use it.

**Files:** `TAKInstall/PSScriptAnalyzerSettings.psd1` (new), `.github/workflows/ci.yml`

---

## Medium Priority

### 4. Harden `/etc/takserver_renew.conf` permissions

**Problem:** `takserver_renewLECerts.sh` creates `/etc/takserver_renew.conf` containing Let's Encrypt renewal credentials (domain, email, API keys) without setting restrictive file permissions. The file could be world-readable.

**Recommendation:** Add `chmod 600 /etc/takserver_renew.conf` after the file is created in `takserver_createLECerts.sh`.

**Files:** `InstallShellScripts/takserver_createLECerts.sh`, its TXT mirror

---

### 5. Add `mkdir -p /atakciv/` guard to Openfire installer

**Problem:** `openfire_takChat_install.sh` hardcodes `/atakciv/` as the download destination but doesn't ensure the directory exists. If the path doesn't exist, `wget` will fail.

**Recommendation:** Add `mkdir -p /atakciv/` before the download command.

**Files:** `InstallShellScripts/openfire_takChat_install.sh`, its TXT mirror

---

### 6. Add hash verification for Openfire download

**Problem:** The Openfire RPM is downloaded from GitHub at runtime with no checksum or GPG signature verification. A compromised mirror or MITM could substitute a malicious package.

**Recommendation:** Add a SHA256 hash check after downloading the RPM:
```bash
EXPECTED_HASH="<sha256>"
echo "$EXPECTED_HASH  /atakciv/openfire-*.rpm" | sha256sum -c -
```

**Files:** `InstallShellScripts/openfire_takChat_install.sh`, its TXT mirror

---

### 7. Collect Total Memory in deployment report

**Problem:** The deployment report shows an empty "Total Memory" field because the `free -h | grep Mem | awk '{print $2}'` command output parsing fails over SSH when the awk field reference collides with PowerShell variable expansion.

**Recommendation:** Escape the awk command or use a heredoc-style approach:
```powershell
$memInfo = (Invoke-SSHCommand -SessionId $session.SessionId -Command "free -h | awk '/Mem/{print `$2}'").Output -join ''
```

**Files:** `Deploy-TAKServer.ps1` (around line 720)

---

## Low Priority

### 8. Add Deploy-TAKServer.ps1 and Deploy-TAKTestServer.ps1 to PSScriptAnalyzer CI

**Problem:** The two orchestration scripts at the repo root are not linted by CI. They follow module conventions but could drift.

**Recommendation:** Add a CI step to lint the root `.ps1` files:
```yaml
- name: Lint root scripts
  run: Invoke-ScriptAnalyzer -Path ./Deploy-TAKServer.ps1, ./Deploy-TAKTestServer.ps1 -Recurse
```

---

### 9. Consider validating `sed` patching of `cert-metadata.sh`

**Problem:** `createTakCerts.sh` uses `sed -i` to replace placeholder values in `cert-metadata.sh`. If the placeholder format changes in a future TAK Server release, `sed` silently does nothing. The CoreConfig.xml validation was already added, but `cert-metadata.sh` patching is still unguarded.

**Recommendation:** After each `sed -i` command, grep for the expected value and fail if not found:
```bash
grep -q "^STATE=$STATE" /opt/tak/certs/cert-metadata.sh || { echo "FATAL: STATE not patched"; exit 1; }
```

---

### 10. Add a `CHANGELOG.md` entry for the wiki migration

**Problem:** The wiki was moved from in-repo `Wiki/` to GitHub Wiki, `Documentation/Wiki/` was removed, and `README.md` was updated — but `CHANGELOG.md` has no entry for this structural change.

**Recommendation:** Add an entry under the current date documenting the migration.

---

## Summary

| Priority | Count | Key Themes |
|----------|-------|------------|
| High | 3 | Test timing fix, CI coverage gap, analyzer settings |
| Medium | 4 | Security hardening, robustness, report accuracy |
| Low | 3 | Extended CI coverage, validation, documentation |
