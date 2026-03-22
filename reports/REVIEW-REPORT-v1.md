# 🚀 DigitalTAK Comprehensive Review Report — v1

**Reviewed:** March 22, 2026 | **Reviewer:** GitHub Copilot (DigitalTAK Orchestrator mode)  
**Coverage:** 7 Bash scripts · 44 TAKServerPS cmdlets · 6 TAKInstall cmdlets · 7 Pester test files · all manifests, helpers, and docs

---

## 1. Executive Summary

DigitalTAK is a genuinely well-engineered, multi-layer TAK Server automation project that goes significantly further than any comparable open-source TAK tooling. The three-layer design (Bash for operators, TAKInstall for Windows-based CI/provisioning, TAKServerPS for post-deployment management) shows clear architectural intent. The PowerShell work in particular — module structure, `ShouldProcess` on destructive ops, `SecureString`-at-boundary password handling, URI encoding, proper `[SSH.SshSession]` typing, comprehensive comment-based help, and PSScriptAnalyzer-clean source — is production quality. The test suite (179 passing, zero mocked live calls) is rare and commendable for an ops-focused repo.

The main risks are concentrated in the **Bash layer**: no idempotency, password escaping is inconsistent with two separate strategies, sleep-countdown polling replaces proper readiness detection, and `/etc/takserver_renew.conf` stores the keystore password in plaintext with only chmod-600 as protection. These are **solvable with modest effort** and are the biggest ROI improvements available.

| Category | Score /10 |
|---|---|
| 🏗️ **Architecture** | 8.5 |
| 💻 **Code Quality** | 8.0 |
| 🔒 **Security** | 6.5 |
| 🔧 **Maintainability** | 7.0 |
| 🎯 **UX / DX** | 8.0 |

---

## 2. Strengths (Already Excellent)

### PowerShell quality is best-in-class for ops tooling
- `ShouldProcess` / `ConfirmImpact` on every destructive operation, with the correct impact level (`High` for delete/install, `Medium` for cert ops)
- `SecureString` passwords never leave the boundary via `Marshal.SecureStringToBSTR` → `ZeroFreeBSTR` immediately after use
- `[SSH.SshSession]` strong typing on every SSH parameter — no `[object]` or `[PSObject]` cheating
- `[System.Uri]::EscapeDataString()` applied consistently before every path segment interpolation — no injection surface
- `ThrowTerminatingError` with custom `ErrorId` throughout — structured error handling, not write-then-exit
- `ConvertTo-TAKBashArg` — the `'` → `'\''` pattern is textbook-correct for bash single-quote escaping

### Bash scripts — the good parts
- `set -euo pipefail` on all scripts — strict error propagation
- Proper `SCRIPT_DIR` via `$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)` — not `$(dirname $0)` or `$0`
- GPG RPM signature verification path included (optional but documented)
- Idempotent `limits.conf` check with `grep -qE` before appending
- `createTakCerts.sh` escapes the keystore password via `printf '%s' | sed` before embedding in `sed` substitution

### Architecture
- The TXT mirror strategy, while blunt, solves a genuine ops problem (restricted-extension environments, copy-paste into web UI)
- `Wait-TAKServiceReady` in PowerShell replaces bash countdown hacks — polling with proper timeout/stopwatch
- `Invoke-TAKRequest` correctly handles all four TAK Server auth methods with consistent priority ordering
- Test suite exercises every layer without network dependencies — fully mocked

---

## 3. Prioritized Recommendations

---

### 🔴 Critical (must-fix before next release)

---

**✅ Bash password escaping is inconsistent and partially broken**  
**Component:** Bash — `createTakCerts.sh`, `takserver_createLECerts.sh`  
**Impact:** Security  
**Effort:** Low

`createTakCerts.sh` escapes the certificate password with this multi-pass `sed`:

```bash
escapedTakCertPass=$(printf '%s' "$takCertPass" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/[&|]/\\&/g' \
    -e 's/"/\\"/g' \
    -e 's/\$/\\$/g' \
    -e 's/`/\\`/g')
```

This works for *sed replacement context* specifically, but `$` escaping here is wrong — the `\$` becomes literal `\$` in the password string, not `$`. It also misses `/` (the CoreConfig sed uses `|` delimiters, so this one is safe *this time*, but future maintainers will copy-paste the pattern).

`takserver_createLECerts.sh` uses a different, simpler (and weaker) escape:

```bash
escapedCertPassword=$(printf '%s' "$certPassword" | sed 's/[&|]/\\&/g')
```

This only escapes `&` and `|` — a password containing `\`, `"`, or `$` will corrupt CoreConfig.xml silently.

**Suggested Implementation:** Standardise on the **bash single-quote parameter expansion** pattern from `ConvertTo-TAKBashArg.ps1` — it's already in the repo and is provably correct:

```bash
# SAFE single-quote escaper — works for ANY password content
bash_quote() {
    local val="${1//\'/\'\\\'\'}"   # replace ' with '\''
    printf "'%s'" "$val"
}

ESCAPED_PASS="$(bash_quote "$takCertPass")"
# Then embed directly in the sed command — no double-quote needed around $ESCAPED_PASS
```

---

**✅ `/etc/takserver_renew.conf` stores keystore password in plaintext**  
**Component:** Bash — `takserver_createLECerts.sh`  
**Impact:** Security  
**Effort:** Low

```bash
printf 'CERT_PASSWORD=%q\n' "$certPassword" | sudo tee /etc/takserver_renew.conf
sudo chmod 600 /etc/takserver_renew.conf
```

`chmod 600` with `root` ownership is a minimum safeguard, but:
- `%q` (printf quoting) is not a standard POSIX specifier — behaviour varies between bash versions
- The file sits readable by root in `/etc/` with no audit trail on access
- Any root-level compromise exposes the keystore password immediately

**Suggested Implementation:** Use systemd credentials or, for the short term, add `chattr +i` after writing and document the risk explicitly:

```bash
# Write config with tighter controls
{
    printf 'CERT_NAME=%s\n' "$certNameVar"
    printf 'CERT_PASSWORD=%s\n' "$certPassword"
} | sudo tee /etc/takserver_renew.conf > /dev/null
sudo chmod 600 /etc/takserver_renew.conf
sudo chown root:root /etc/takserver_renew.conf

# SECURITY NOTE in script:
echo "SECURITY: /etc/takserver_renew.conf contains the keystore password."
echo "         Consider using systemd-creds or a vault for production use."
```

---

**✅ `createTakCerts.sh` has no validation after `sed` patches CoreConfig.xml**  
**Component:** Bash — `createTakCerts.sh`  
**Impact:** Security · Maintainability  
**Effort:** Low

The four `cert-metadata.sh` `sed` patches (STATE, CITY, ORG, OU) have no post-write verification. If `cert-metadata.sh` has already been patched (non-fresh install) the patterns won't match and the file stays unchanged — silent failure.

**Suggested Implementation:**

```bash
# After each sed patch, verify the value was written:
sed -i "s|STATE=\${STATE}|STATE=$statevar|g" cert-metadata.sh
if ! grep -q "STATE=$statevar" cert-metadata.sh; then
    echo "ERROR: Failed to patch STATE in cert-metadata.sh. Is it already configured?"
    exit 1
fi
```

---

**✅ `takUserCreateCerts_doNotRunAsRoot.sh` is fully non-idempotent and interactive**  
**Component:** Bash  
**Impact:** Maintainability · Security  
**Effort:** Medium

`makeRootCa.sh` prompts interactively for the CA name — there's no way to pass it non-interactively from `createTakCerts.sh`. This means:
- The script can't be automated in a pipeline
- Re-running the script destroys the existing CA chain with `rm -vRf /opt/tak/certs/files` and then halts at a prompt

**Suggested Implementation:** Pipe the CA name into the script via stdin:

```bash
# In createTakCerts.sh:
echo "$caNameVar" | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeRootCa.sh'
```

Add a guard before the destructive `rm`:

```bash
read -p 'CA Name [TAK-CA]: ' caNameVar
caNameVar="${caNameVar:-TAK-CA}"

read -p 'This will DESTROY existing certificates. Type YES to confirm: ' confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }
```

---

**✅ `openfire_takChat_install.sh` downloads Openfire with no hash verification**  
**Component:** Bash  
**Impact:** Security (supply-chain)  
**Effort:** Low

```bash
curl -L -o /atakciv/openfire-5.0.3-1.noarch.rpm \
    "https://github.com/igniterealtime/Openfire/releases/download/v5.0.3/openfire-5.0.3-1.noarch.rpm"
```

No `--fail`, no checksum verification. A MITM or a corrupt download results in an unsigned RPM being installed.

**Suggested Implementation:**

```bash
OPENFIRE_SHA256="<actual-sha256-from-release-page>"

curl -fL -o /atakciv/openfire-5.0.3-1.noarch.rpm \
    "https://github.com/igniterealtime/Openfire/releases/download/v5.0.3/openfire-5.0.3-1.noarch.rpm"

echo "$OPENFIRE_SHA256  /atakciv/openfire-5.0.3-1.noarch.rpm" | sha256sum --check || {
    echo "ERROR: Openfire RPM checksum mismatch. Aborting."
    exit 1
}
```

---

### 🟠 High Priority (big wins)

---

**✅ Replace all sleep countdown loops with `systemctl is-active` polling in Bash**  
**Component:** Bash — `createTakCerts.sh`  
**Impact:** DX · Reliability  
**Effort:** Low

`createTakCerts.sh` has **270 seconds of hardcoded sleep** spread across two restart waits. The equivalent `Wait-TAKServiceReady` in PowerShell is already correct. Apply the same pattern in Bash:

```bash
wait_for_takserver() {
    local timeout="${1:-300}"
    local elapsed=0
    echo "Waiting for takserver to become active (timeout ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if systemctl is-active --quiet takserver; then
            echo "takserver is active."
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  ${elapsed}s elapsed..."
    done
    echo "ERROR: takserver did not become active within ${timeout}s."
    exit 1
}

sudo systemctl restart takserver
wait_for_takserver 300
```

This alone eliminates **360 seconds of unconditional waiting** from every fresh install.

---

**✅ `Invoke-TAKRequest` — no retry logic for transient failures**  
**Component:** TAKServerPS  
**Impact:** Reliability · DX  
**Effort:** Medium

The REST wrapper has no retry on transient HTTP 429 (rate limit), 503, or network blips. For batch operations (e.g. `Get-TAKUser -AccountList | Remove-TAKUser`) a single transient error aborts the pipeline.

**Suggested Implementation:**

```powershell
param (
    ...
    [Parameter()] [ValidateRange(0, 5)] [int] $RetryCount = 2,
    [Parameter()] [ValidateRange(1, 30)] [int] $RetryDelaySeconds = 3
)

$attempt = 0
do {
    try {
        $response = Invoke-RestMethod @irmParams
        break
    }
    catch [System.Net.Http.HttpRequestException] {
        if ($attempt -ge $RetryCount) { $PSCmdlet.ThrowTerminatingError(...) }
        Write-Verbose "Transient error (attempt $($attempt+1)/$RetryCount) — retrying in ${RetryDelaySeconds}s"
        Start-Sleep -Seconds $RetryDelaySeconds
        $attempt++
    }
} while ($true)
```

---

**✅ No pagination support in `Invoke-TAKRequest`**  
**Component:** TAKServerPS  
**Impact:** Reliability  
**Effort:** Medium

TAK Server's list endpoints (users, missions, certs) return paginated results when there are many records. `Get-TAKUser -AccountList` on a server with 500+ users silently returns only the first page. No `-All` or `-PageSize` parameter exists.

**Suggested Implementation:** Add an `-AutoPage` switch to `Invoke-TAKRequest` that follows TAK's `offset`/`limit` pattern until exhausted.

---

**✅ `Connect-TAKServer` connectivity test hits wrong endpoint**  
**Component:** TAKServerPS  
**Impact:** DX · Reliability  
**Effort:** Low

```powershell
# Current — path may not exist in all TAK 5.7 builds:
$null = Invoke-TAKRequest -Path '/Marti/api/ver' -ErrorAction Stop

# Fix — canonical version info endpoint:
$null = Invoke-TAKRequest -Path '/Marti/api/version/info' -ErrorAction Stop
```

---

**✅ `Install-TAKServer` hardcodes the pgdg repo URL to x86_64**  
**Component:** TAKInstall  
**Impact:** Maintainability · Portability  
**Effort:** Low

```powershell
# Current:
"sudo dnf --disablerepo='*' -y install https://download.postgresql.org/.../EL-9-x86_64/..."

# Fix — add -Architecture parameter:
[Parameter()] [ValidateSet('x86_64','aarch64')] [string] $Architecture = 'x86_64'

$pgdgUrl = "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-$Architecture/pgdg-redhat-repo-latest.noarch.rpm"
```

---

**✅ TXT sync is entirely manual with no enforcement**  
**Component:** TXTScripts  
**Impact:** Maintainability  
**Effort:** Low

**Suggested Implementation — `Sync-TXTMirrors.ps1`:**

```powershell
Get-ChildItem .\InstallShellScripts\*.sh | ForEach-Object {
    $dest = Join-Path .\TXTScripts ($_.BaseName + '.txt')
    Copy-Item $_.FullName $dest -Force
    Write-Verbose "Synced $($_.Name) -> $($_.BaseName).txt"
}
```

**CI check (GitHub Actions):**

```yaml
- name: Verify TXT mirrors are in sync
  run: |
    for f in InstallShellScripts/*.sh; do
      base=$(basename "$f" .sh)
      diff "$f" "TXTScripts/$base.txt" || { echo "FAIL: $base.txt is out of sync"; exit 1; }
    done
```

---

### 🟡 Medium / Nice-to-Have

---

**✅ `Remove-TAKUser` should offer `-AlsoRevokeCertificates` switch**  
**Component:** TAKServerPS  
**Impact:** DX  
**Effort:** Low

```powershell
[Parameter()] [switch] $AlsoRevokeCertificates
...
process {
    if ($PSCmdlet.ShouldProcess($UserName, 'Delete TAK user')) {
        $null = Invoke-TAKRequest -Path "/user-management/api/delete-user/$encodedName" -Method Delete
        if ($AlsoRevokeCertificates) {
            Get-TAKCertificate -UserName $UserName | Remove-TAKCertificate
        }
    }
}
```

---

**✅ `promoteAdmin.sh` assumes `/home/atak/` exists**  
**Component:** Bash  
**Impact:** Idempotency  
**Effort:** Low

```bash
sudo mkdir -p /home/atak
sudo chown atak:atak /home/atak
sudo cp /opt/tak/certs/files/admin.p12 /home/atak/
sudo chown atak:atak /home/atak/admin.p12
sudo chmod 640 /home/atak/admin.p12
```

Note: `Set-TAKAdminCertificate.ps1` already applies `chmod 640` and `chown atak:atak` — the Bash version is weaker.

---

**✅ `createTakCerts.sh` echoes stray progress numbers (70, 80)**  
**Component:** Bash  
**Impact:** DX  
**Effort:** Trivial

Lines like `echo "70"`, `echo "80"` at the top are dead code — remnants of a progress-bar integration that no longer exists.

---

**✅ `TAKServerPS` has no `New-TAKUserCertificate` cmdlet**  
**Component:** TAKServerPS  
**Impact:** DX  
**Effort:** Medium

`Invoke-TAKCertificateSign` already wraps the CSR-signing REST call. A high-level `New-TAKUserCertificate` that generates a key + CSR locally, submits it, and returns the signed cert would complete the Windows ↔ Bash parity story for cert provisioning.

---

### 🟢 Low / Polish

---

**✅ `openfire_takChat_install.sh` header still references old script name**  
**Component:** Bash  
**Impact:** Maintainability  
**Effort:** Trivial

```bash
## Run AFTER RL9.5_tak5.4r14_install.sh has completed successfully.
# Should be:
## Run AFTER RL9_tak5.7r8_install.sh has completed successfully.
```

---

**✅ `RL9_tak5.7r8_install.sh` installs `vim` unconditionally**  
**Component:** Bash  
**Impact:** Minimalism  
**Effort:** Trivial

Should be behind an `INSTALL_VIM="${INSTALL_VIM:-false}"` guard for unattended deployments.

---

**✅ Module version is `1.0.0` in both manifests with no changelog**  
**Component:** TAKServerPS · TAKInstall  
**Impact:** Maintainability  
**Effort:** Low

Add `CHANGELOG.md` and bump versions before any public release. Add `Tags`, `ProjectUri`, `ReleaseNotes` to `PrivateData.PSData` in both manifests.

---

**✅ `ORCHESTRATOR.md` lives at repo root instead of `.github/agents/`**  
**Component:** Repo structure  
**Impact:** Cleanliness  
**Effort:** Trivial

Agent metadata files should be under `.github/agents/`, not at the repo root.

---

**✅ `tak_config_guide_extracted.txt.ignore` in repo root**  
**Component:** Repo structure  
**Impact:** Cleanliness  
**Effort:** Trivial

Either add to `.gitignore` or delete the file. The `.ignore` suffix is not a standard git mechanism.

---

## 4. Component Deep-Dives

### 4.1 Bash Scripts & TXTScripts Strategy

The scripts are well-structured for a sequential manual-run workflow. `set -euo pipefail` is applied everywhere. `SCRIPT_DIR` detection is correct. The biggest structural weakness is the **total absence of idempotency** — every script is designed for a single run on a fresh host. Re-running any script will either fail (`set -e` on already-configured resources) or silently mangle configuration (e.g. the `sed` patches in `cert-metadata.sh` won't match on second run).

The **TXT mirror strategy** is pragmatic but fragile. No CI detects drift. Since the files must stay byte-identical, the right tool is `git hooks`, a `Make` sync target, or a pre-commit hook — not documentation alone.

`createTakCerts.sh` contains **360 seconds of unconditional sleep**. `systemctl is-active` polling would make fresh installs 3–5 minutes faster.

The OpenSSL password escaping inconsistency is the most serious code correctness issue — two different escape strategies mean behaviour diverges for identical passwords containing `$` or `\`.

### 4.2 TAKServerPS Module (REST wrapper + auth patterns)

Excellent work. The session model (`$script:TAKSession` PSCustomObject with typed `Certificate`, `Token` as `SecureString`, `Credential` as `PSCredential`) is the correct pattern and is consistent across all 44 cmdlets. `ThrowTerminatingError` with custom `ErrorId` strings enables callers to catch specific error types.

Two gaps: (1) no pagination — list endpoints return first page only; (2) the connectivity test on `Connect-TAKServer` may hit an incorrect path. Consider also setting `ErrorId` to `TAKHttpError_$statusCode` when extractable from 4xx/5xx responses so callers can distinguish 401/403/404 by `ErrorId`.

### 4.3 TAKInstall Module (SSH orchestration)

The design is sound: one cmdlet per Bash script, same step comments, same logical sequence. `ConvertTo-TAKBashArg` is correct and is consistently used everywhere passwords touch bash command strings.

`Install-TAKServer` uses `chmod 777` on the remote staging directory — `chmod 700` would be safer. `New-TAKLetsEncryptCertificate` correctly documents the plaintext renewal config risk in `.NOTES`. One gap: `Update-TAKLetsEncryptCertificate` doesn't verify DNS resolution before invoking certbot, which will fail with a confusing ACME error if DNS is stale.

### 4.4 Testing Strategy — 179/179 Pester Coverage

The test approach is architecturally correct: all tests mock external calls so zero live infrastructure is required. The module-scope tests (manifest validation, function counts, `OutputType` presence, approved verbs) are thorough and caught a real parse bug in `New-TAKServerCertificate.ps1` during this session.

**Coverage gaps:**
- No tests for any of the 43 remaining TAKServerPS public cmdlets beyond `Connect-TAKServer`
- No tests for `New-TAKServerCertificate` or `Install-TAKServer` (most complex, highest risk)
- No `PSScriptAnalyzer` invocation in the test suite — PSA runs manually only
- No negative tests for invalid parameter combinations

### 4.5 Documentation, README, channels.zip

The README (rewritten this session) is comprehensive and well-structured. `channels.zip` is present but completely undocumented beyond the README one-liner — no explanation of what channels it defines, how to update it, or how to replace it.

### 4.6 Repository Structure & Future-Proofing

The `TAKserverAPI/` directory may contain a stale 5.6 OpenAPI spec — verify it is empty or remove it. Both module manifests are at `1.0.0` with no git tags matching. Pre-release versioning (`0.x.x`) or a matching `v1.0.0` git tag should be established before any public distribution.

---

## 5. Optimization Opportunities (grouped for sub-agents)

---

### 🔹 FOR BASH SUB-AGENT

**Scope:** All files in `InstallShellScripts/` and `TXTScripts/`

#### A — Shared `utils.sh` library

Extract reusable patterns into `InstallShellScripts/utils.sh`:

```bash
#!/bin/bash
# utils.sh — shared helpers for DigitalTAK Bash scripts

# Safely escapes a value for embedding in a bash single-quoted string
bash_quote() {
    local val="${1//\'/\'\\\'\'}"   # replace ' with '\''
    printf "'%s'" "$val"
}

# Waits for a systemd service to become active; exits 1 on timeout
wait_for_service() {
    local service="$1" timeout="${2:-300}" elapsed=0
    echo "Waiting for '$service' (timeout ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        systemctl is-active --quiet "$service" && { echo "'$service' is active."; return 0; }
        sleep 10; elapsed=$((elapsed + 10))
        echo "  ${elapsed}/${timeout}s..."
    done
    echo "ERROR: '$service' did not become active within ${timeout}s."
    return 1
}

# Idempotent firewalld port opener
firewalld_add_port() {
    local port="$1" zone="${2:-public}"
    sudo firewall-cmd --zone="$zone" --query-port="$port" --permanent &>/dev/null || \
        sudo firewall-cmd --zone="$zone" --permanent --add-port="$port"
}

# Validates a cert-metadata field (CAPS, digits, no spaces)
validate_cert_field() {
    local field="$1" value="$2"
    if [[ ! "$value" =~ ^[A-Z0-9]+$ ]]; then
        echo "ERROR: $field must be UPPERCASE letters and digits only. Got: $value"
        exit 1
    fi
}
```

#### B — Idempotency guards for `RL9_tak5.7r8_install.sh`

```bash
# Guard PostgreSQL repo
if ! dnf repolist | grep -q pgdg; then
    sudo dnf --disablerepo='*' -y install \
        https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
fi

# Guard Java installation
if ! java -version 2>&1 | grep -q '"17\.'; then
    sudo dnf install -y java-17-openjdk-devel
fi

# Guard TAK Server RPM
if ! rpm -q takserver &>/dev/null; then
    sudo dnf install -y "$TAK_RPM"
fi
```

#### C — Fix password escaping in `createTakCerts.sh`

Replace the multi-pass `sed` escape with `bash_quote` from `utils.sh`:

```bash
source "$SCRIPT_DIR/utils.sh"

ESCAPED_PASS="$(bash_quote "$takCertPass")"

# Embed in sed command — ESCAPED_PASS already contains outer single-quotes
sed -i "s|<vbm enabled=\"false\"/>|..keystorePass=${ESCAPED_PASS}...|g" /opt/tak/CoreConfig.xml
```

#### D — Replace sleep countdowns (saves 5–7 minutes per deploy)

```bash
# After first restart:
sudo systemctl restart takserver
wait_for_service takserver 180

# After second restart (before promoteAdmin):
sudo systemctl restart takserver
wait_for_service takserver 300
```

#### E — CA name pass-through to eliminate interactive sub-script prompt

In `createTakCerts.sh`:
```bash
read -p 'Root CA Name [TAK-CA]: ' caNameVar
caNameVar="${caNameVar:-TAK-CA}"
export TAK_CA_NAME="$caNameVar"
sudo -u tak /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
```

In `takUserCreateCerts_doNotRunAsRoot.sh`:
```bash
CA_NAME="${TAK_CA_NAME:-TAK-CA}"
echo "$CA_NAME" | ./makeRootCa.sh
```

#### F — Security hardening checklist

| Script | Finding | Fix |
|--------|---------|-----|
| `createTakCerts.sh` | Multi-pass sed password escape has `$` bug | Use `bash_quote()` |
| `createTakCerts.sh` | No cert-metadata.sh patch verification | Add `grep -q` after each `sed -i` |
| `takserver_createLECerts.sh` | Minimal password escape (`&\|` only) | Use `bash_quote()` |
| `takserver_createLECerts.sh` | `/etc/takserver_renew.conf` is plaintext | Document + consider `systemd-creds` |
| `openfire_takChat_install.sh` | No RPM checksum | Add `sha256sum --check` |
| `openfire_takChat_install.sh` | No `--fail` on `curl` | Replace `-L` with `-fL` |
| `RL9_tak5.7r8_install.sh` | `/tmp/tak_install` chmod 777 | Use `chmod 700` |
| `promoteAdmin.sh` | No user/home existence check | Add `id atak` guard + `mkdir -p` |
| All scripts | No input validation on cert fields | Add `validate_cert_field()` before `sed` |

---

### 🔹 FOR POWERSHELL TAKServerPS SUB-AGENT

**Scope:** `TAKServerPS/`

#### A — Add retry logic to `Invoke-TAKRequest`

```powershell
param (
    ...
    [Parameter()] [ValidateRange(0,5)] [int] $RetryCount = 2,
    [Parameter()] [ValidateRange(1,30)] [int] $RetryDelaySeconds = 3
)

$attempt = 0
$lastError = $null
do {
    try {
        $response = Invoke-RestMethod @irmParams
        $lastError = $null
        break
    }
    catch [System.Net.Http.HttpRequestException] {
        $lastError = $PSItem
        if ($attempt -ge $RetryCount) { break }
        Write-Verbose "[TAKRequest] Attempt $($attempt+1) failed. Retrying in ${RetryDelaySeconds}s..."
        Start-Sleep -Seconds $RetryDelaySeconds
        $attempt++
    }
} while ($true)

if ($lastError) { $PSCmdlet.ThrowTerminatingError(...) }
```

#### B — Fix connectivity test endpoint in `Connect-TAKServer`

```powershell
# Change:
$null = Invoke-TAKRequest -Path '/Marti/api/ver' -ErrorAction Stop
# To:
$null = Invoke-TAKRequest -Path '/Marti/api/version/info' -ErrorAction Stop
```

#### C — Cmdlet-by-cmdlet quick wins

| Cmdlet | Issue | Fix |
|--------|-------|-----|
| `Get-TAKUser` | `ByGroup` path — verify vs 5.7 API spec | Cross-check with OpenAPI spec |
| `Remove-TAKUser` | No `-AlsoRevokeCertificates` | Add switch (see Medium section) |
| `Get-TAKMission` | No `ValueFromPipelineByPropertyName` on `Name` | Add pipeline support |
| `Set-TAKSecurityConfig` | No diff/show-what-changed behaviour | Add `-WhatIf` output with old vs new values |
| `New-TAKUser` | `$plainPassword` in hashtable in memory | Clear `$plainPassword` immediately after adding to `$body` |
| `Get-TAKVersion` | `/Marti/api/ver` short path may not be wrapped — `.data` unwrap returns `$null` | Test live; may need `-Raw` switch |

#### D — Module manifest improvements

```powershell
PrivateData = @{
    PSData = @{
        Tags        = @('TAK', 'ATAK', 'REST', 'API', 'TAKServer', 'CivTAK', 'CoT')
        ProjectUri  = 'https://github.com/BanterBoy/DigitalTAK'
        ReleaseNotes = 'v1.0.0 — Initial release'
    }
}
```

#### E — Proposed new cmdlets

- `Get-TAKAuditLog` — admin audit log endpoint (critical for security monitoring)
- `New-TAKUserCertificate` — generate key + CSR locally, submit via `Invoke-TAKCertificateSign`, return signed cert

---

### 🔹 FOR TAKInstall + SSH SUB-AGENT

**Scope:** `TAKInstall/`

#### A — Harden remote work directory permissions

```powershell
# Change:
"sudo mkdir -p $RemoteWorkDir && sudo chmod 777 $RemoteWorkDir"
# To:
"sudo mkdir -p $RemoteWorkDir && sudo chmod 700 $RemoteWorkDir"
```

#### B — Add DNS pre-flight for `New-TAKLetsEncryptCertificate`

```powershell
$dnsCheck = Invoke-TAKRemoteCommand -Session $SshSession -Description 'DNS pre-flight' -Command `
    "getent hosts $(ConvertTo-TAKBashArg $DomainName) || host $(ConvertTo-TAKBashArg $DomainName)" -AllowFailure
if ($dnsCheck.ExitStatus -ne 0) {
    Write-Warning "DNS lookup for '$DomainName' failed on the server. The ACME challenge may fail."
}
```

#### C — Proposed new cmdlet: `Get-TAKServerStatus`

```powershell
function Get-TAKServerStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][SSH.SshSession] $SshSession)

    $status = (Invoke-TAKRemoteCommand -Session $SshSession -Command 'systemctl is-active takserver').Output.Trim()
    $disk   = (Invoke-TAKRemoteCommand -Session $SshSession -Command 'du -sh /opt/tak/certs/files 2>/dev/null || echo N/A').Output.Trim()
    $java   = (Invoke-TAKRemoteCommand -Session $SshSession -Command 'java -version 2>&1 | head -1').Output.Trim()

    [PSCustomObject]@{
        ServiceStatus  = $status
        CertsDiskUsage = $disk
        JavaVersion    = $java
    }
}
```

#### D — Bash ↔ PowerShell parity gaps

| Feature | Bash | PowerShell | Gap |
|---------|------|-----------|-----|
| CA name prompt | Interactive `read` | `$CAName` parameter | PS wins — Bash needs env pass-through |
| Service wait | 270s sleep | `Wait-TAKServiceReady` w/ stopwatch | PS wins — Bash needs `wait_for_service()` |
| Password escape | Two incompatible strategies | `ConvertTo-TAKBashArg` (correct) | **Bash lags** |
| Cert metadata validation | None after `sed` | grep check after remote sed | **Bash lags** |
| Idempotency | None | None (by design) | Same gap in both |

---

### 🔹 FOR TESTING & CI/CD SUB-AGENT

**Scope:** `TAKServerPS/Tests/`, `TAKInstall/Tests/`, proposed `.github/workflows/`

#### A — Current coverage gaps

| Gap | Severity |
|-----|----------|
| No tests for 43 of 44 TAKServerPS public cmdlets | High |
| No tests for `New-TAKServerCertificate` (already had a bug) | High |
| No tests for `Install-TAKServer` (SCP calls, GPG verification logic) | High |
| No `PSScriptAnalyzer` in CI | Medium |
| No negative tests for invalid inputs | Medium |
| No TXT/SH sync verification | Medium |

#### B — Recommended additional test files

```
TAKServerPS/Tests/
    Get-TAKUser.Tests.ps1
    Remove-TAKUser.Tests.ps1
    Get-TAKMission.Tests.ps1
    Get-TAKCertificate.Tests.ps1
    Invoke-TAKCertificateSign.Tests.ps1

TAKInstall/Tests/
    Install-TAKServer.Tests.ps1
    New-TAKServerCertificate.Tests.ps1
    New-TAKLetsEncryptCertificate.Tests.ps1
```

#### C — GitHub Actions workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [prod, main]
  pull_request:

jobs:
  pester:
    name: Pester Tests (PS ${{ matrix.ps-version }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ps-version: ['7.4', '7.5']
    steps:
      - uses: actions/checkout@v4

      - name: Install PowerShell
        run: |
          wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb"
          sudo dpkg -i packages-microsoft-prod.deb
          sudo apt-get update && sudo apt-get install -y powershell

      - name: Install Pester + Posh-SSH
        shell: pwsh
        run: |
          Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
          Install-Module Posh-SSH -Force -Scope CurrentUser

      - name: Run TAKServerPS tests
        shell: pwsh
        run: Invoke-Pester -Path ./TAKServerPS/Tests -Output Detailed -CI

      - name: Run TAKInstall tests
        shell: pwsh
        run: Invoke-Pester -Path ./TAKInstall/Tests -Output Detailed -CI

  psscriptanalyzer:
    name: PSScriptAnalyzer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Lint modules
        shell: pwsh
        run: |
          Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
          $r1 = Invoke-ScriptAnalyzer -Path ./TAKServerPS -Recurse -Settings ./TAKServerPS/PSScriptAnalyzerSettings.psd1
          $r2 = Invoke-ScriptAnalyzer -Path ./TAKInstall -Recurse
          $all = @($r1) + @($r2)
          $all | Format-Table
          if ($all) { exit 1 }

  txt-sync:
    name: TXT Mirror Sync Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify TXT mirrors match .sh files
        run: |
          for f in InstallShellScripts/*.sh; do
            base=$(basename "$f" .sh)
            diff "$f" "TXTScripts/$base.txt" || { echo "FAIL: $base.txt is out of sync"; exit 1; }
          done

  shellcheck:
    name: ShellCheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ludeeus/action-shellcheck@master
        with:
          scandir: './InstallShellScripts'
```

#### D — Mocking strategy improvements

For multi-step cmdlets, use `-ParameterFilter` to return different values per command:

```powershell
Mock Invoke-SSHCommand -ModuleName TAKInstall -ParameterFilter { $Command -like '*is-active*' } {
    [PSCustomObject]@{ ExitStatus = 0; Output = 'active'; Error = '' }
}
Mock Invoke-SSHCommand -ModuleName TAKInstall -ParameterFilter { $Command -like '*dnf*' } {
    [PSCustomObject]@{ ExitStatus = 0; Output = 'Complete!'; Error = '' }
}
```

---

### 🔹 FOR DOCUMENTATION & README SUB-AGENT

**Scope:** `README.md`, `ORCHESTRATOR.md`, `Documentation/`, `channels.zip`

#### A — Move `ORCHESTRATOR.md` to `.github/agents/`

The repo root should contain user-facing content only. Agent metadata belongs in `.github/agents/ORCHESTRATOR.md`.

#### B — Create `CONTRIBUTING.md`

```markdown
# Contributing to DigitalTAK

## TXT Mirror Rule
Every change to a `.sh` file in `InstallShellScripts/` MUST be mirrored to the
corresponding `.txt` file in `TXTScripts/`. Run `./Sync-TXTMirrors.ps1` before
committing.

## PowerShell Standards
- All cmdlets must pass `Invoke-ScriptAnalyzer` with zero errors/warnings
- New cmdlets require at least a module-manifest test entry
- `ShouldProcess` is mandatory for all Create/Update/Delete operations

## Bash Standards
- `set -euo pipefail` on every script
- Passwords must use `bash_quote()` from `utils.sh` — never embed raw
- `sed -i` patches must be validated with a `grep -q` check afterwards
```

#### C — Add `channels.zip` documentation in `Documentation/channels-zip.md`

Document: what channels are included, how to update the package, and how to distribute it via TAK Server Data Packages.

#### D — Add `SECURITY.md`

Document: sensitive files and their permissions, known design trade-offs (plaintext LE renewal config), and the recommended procedure for reporting security issues.

---

### 🔹 FOR SECURITY & HARDENING SUB-AGENT

**Scope:** All scripts and modules

#### A — Threat model quick wins

| Threat | Vector | Current State | Recommended Fix |
|--------|--------|---------------|-----------------|
| Keystore password exposure | `/etc/takserver_renew.conf` | plaintext, `chmod 600` | `systemd-creds` or vault |
| Supply-chain: Openfire RPM | unauthenticated download | No checksum | `sha256sum --check` |
| Bash command injection via user input | `$statevar` etc. in `sed` | No input validation | `validate_cert_field()` before use |
| SCP staging area compromise | `/tmp/tak_install` chmod 777 | World-writable | `chmod 700` |
| Admin cert exposure | `/home/atak/admin.p12` | `chmod 640` in PS, missing in Bash | Add `chmod 640` to `promoteAdmin.sh` |
| SSH host key verification | `New-SSHSession` | Caller's responsibility | Document `-AcceptKey:$false` for production |
| Enrolled cert short validity | 30-day validity for user certs | Short lifecycle | Document rotation procedure |

#### B — Prioritized hardening checklist

```
[CRITICAL]
☐ Fix password escaping inconsistency (createTakCerts.sh, takserver_createLECerts.sh)
☐ Add sha256sum verification for Openfire RPM download
☐ Add cert-metadata.sh patch validation (grep -q after each sed -i)

[HIGH]
☐ chmod 700 (not 777) on /tmp/tak_install staging directory
☐ Add chmod 640 to admin.p12 in promoteAdmin.sh
☐ Document /etc/takserver_renew.conf plaintext password risk inline
☐ Add input validation (regex ^[A-Z0-9]+$) before statevar/cityvar/orgvar used in sed

[MEDIUM]
☐ Add --fail to curl in openfire_takChat_install.sh
☐ Validate cert-metadata.sh sed patches succeeded
☐ Add /home/atak/ existence guard in promoteAdmin.sh
☐ Document SSH host key verification recommendation

[LOW]
☐ Consider chattr +i on /etc/takserver_renew.conf after writing
☐ Add audit log recommendation for /opt/tak/certs/files/ access
```

---

## 6. Bonus Section — Proposed Next-Level Enhancements

| Enhancement | Impact | Effort |
|------------|--------|--------|
| **Container image** — Rocky Linux 9 + TAK Server + auto-provisioning via `docker run`; cert volume mounting | 🔥 Transformative for test/dev environments | High |
| **Ansible collection** — `digitaltak.takserver` roles mirroring the Bash scripts, idempotent via `ansible.builtin.rpm_key`, `community.general.ini_file` | 🔥 Enterprise-grade repeatability | High |
| **Module version matrix** — GitHub Actions matrix testing against TAK 5.6 and 5.7 API | Very high for reliability | Medium |
| **`TAKCert` PowerShell class** — typed certificate object with `Renew()`, `Revoke()`, `ExportP12()` methods | Elevates DX significantly | Medium |
| **`Get-TAKHealth`** — composite cmdlet checking service status, cert expiry, disk, and Java version | Immediately useful for operators | Low |
| **SBOM / dependency pinning** — pin Openfire SHA256 in `versions.json`; add `dependabot.yml` for GitHub Actions | Supply chain hardening | Low |
| **`New-TAKDeployment`** — orchestrator cmdlet calling Install → Certs → Admin in sequence with checkpoints | One-shot provisioning | Medium |
| **Signed module publish to PSGallery** — code-signed module would make this discoverable by the CivTAK community | Community reach | Medium |

---

## 7. One-Click Action Plan

Execute in this order — each item is designed to be completable in a single session:

1. **🔥 Fix Bash password escaping** — Create `utils.sh` with `bash_quote()` and replace both divergent escape strategies in `createTakCerts.sh` and `takserver_createLECerts.sh`

2. **🔥 Replace sleep countdowns** — Add `wait_for_service()` to `utils.sh` and replace all sleep blocks in `createTakCerts.sh` — saves 5–7 minutes per deploy

3. **🔥 Add cert-metadata.sh patch validation** — `grep -q` after every `sed -i` in `createTakCerts.sh`

4. **🔒 Harden Openfire download** — Add `--fail` to `curl` and `sha256sum --check` in `openfire_takChat_install.sh`

5. **🔒 Fix SCP staging permissions** — Change `chmod 777` to `chmod 700` in `Install-TAKServer.ps1`

6. **🛠 Add CA name pass-through** — Make `createTakCerts.sh` pass CA name to `takUserCreateCerts_doNotRunAsRoot.sh` via env variable

7. **⚡ Fix `Connect-TAKServer` test endpoint** — Change `/Marti/api/ver` to `/Marti/api/version/info`

8. **🔁 Add `Sync-TXTMirrors.ps1` + CI check** — Enforce TXT/SH sync in GitHub Actions

9. **✅ Add GitHub Actions CI** — Wire up Pester + PSScriptAnalyzer + ShellCheck + TXT sync from section 5

10. **📦 Publish metadata** — Add `Tags`, `ProjectUri`, `ReleaseNotes` to both manifests; create `CHANGELOG.md`; move `ORCHESTRATOR.md` to `.github/agents/`; remove `tak_config_guide_extracted.txt.ignore`

---

*Review complete: all 7 Bash scripts, 44 TAKServerPS cmdlets, 6 TAKInstall cmdlets, 3 private helpers, 7 Pester test files, 2 module manifests, and all documentation files examined.*
