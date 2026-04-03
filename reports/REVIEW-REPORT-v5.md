# DigitalTAK Comprehensive Review Report — v5

**Reviewed:** 2026-04-03 (Session 5) | **Reviewer:** Paperclip CEO Agent
**Previous Report:** [reports/REVIEW-REPORT-v4.md](reports/REVIEW-REPORT-v4.md)
**Coverage:** `Remove-CivTAK.ps1` — certificate store cleanup

---

## 1. Executive Summary

This session resolves one issue identified post-v4 by the board: the removal script
did not clean up the full TAK certificate chain from the Windows certificate store.

One code change was made:

1. **R1** — `Remove-CivTAK.ps1` Step 5 now matches and removes the root CA,
   intermediate CA, and admin certificates from the Windows store.  Previously
   only the root CA was removed.

| Category | v4 Score | v5 Score | Change |
|---|---|---|---|
| 🏗️ **Architecture** | 8.5 | 8.5 | — |
| 💻 **Code Quality** | 9.0 | 9.0 | — |
| 🔒 **Security** | 8.5 | 8.5 | — |
| 🔧 **Maintainability** | 9.0 | 9.0 | — |
| 🎯 **UX / DX** | 9.0 | 9.0 | — |

---

## 2. Session 5 Changes

### Items Resolved

| # | Severity | Item | Resolution |
|---|---|---|---|
| 1 | 🟠 High | `Remove-CivTAK.ps1` Step 5 skipped intermediate CA and admin cert during Windows store cleanup | Extended filter to match by `Issuer` field and known TAK CNs; added `-CAName` parameter |

---

## 3. Detailed Change Notes

### `Remove-CivTAK.ps1`

#### Root Cause

`Deploy-TAKServer.ps1` imports three certificates into the Windows certificate store:

| Cert | Store | Subject | Issuer |
|---|---|---|---|
| Root CA | `CurrentUser\Root` | `CN=TAK-CA, O=<org>` | self |
| Intermediate CA | `CurrentUser\Root` | `CN=intermediate-ca, O=<org>` | `CN=TAK-CA` |
| Admin cert | `CurrentUser\My` | `CN=admin, O=<org>` | `CN=intermediate-ca` |

The previous Step 5 filter:

```powershell
Where-Object { $_.Subject -match 'O=' -and ($_.Subject -match [regex]::Escape($Organization) -or $_.Subject -match 'TAK-CA') }
```

- Matched the root CA via `'TAK-CA'` in Subject. ✓
- Missed the intermediate CA (`CN=intermediate-ca` — no 'TAK-CA' in Subject). ✗
- Missed the admin cert (`CN=admin` — no 'TAK-CA' in Subject). ✗
- The `$Organization` fallback only matched if the operator passed `-Organization`
  with the exact string used at deployment time (e.g. `'LEIGH-SERVICES'`); the
  default `'TAK'` would not match a deployment that used a different org string. ✗

#### Fix

Added `-CAName 'TAK-CA'` parameter and updated the filter:

```powershell
$caNameEsc = [regex]::Escape($CAName)
$orgEsc    = [regex]::Escape($Organization)

Where-Object {
    $_.Subject -match $caNameEsc -or          # root CA cert
    $_.Issuer  -match $caNameEsc -or          # intermediate CA (issued by root CA)
    $_.Subject -match 'CN=intermediate-ca' -or # intermediate CA by well-known CN
    $_.Issuer  -match 'CN=intermediate-ca' -or # admin cert (issued by intermediate CA)
    ($_.Subject -match 'O=' -and $_.Subject -match $orgEsc)  # org-name fallback
}
```

This reliably removes all three certs without requiring the operator to know
which organisation string was used at deployment time.

Added `-CAName` parameter documentation, updated `.PARAMETER Organization` to
clarify its role as a fallback, and added a `.EXAMPLE` showing correct usage with
non-default org/CA names.

---

## 4. Remaining Open Issues

**None.**

| Severity | Open Count |
|---|---|
| 🔴 Critical | 0 |
| 🟠 High | 0 |
| 🟡 Medium | 0 |
| 🔵 Low | 0 |

---

## 5. Cumulative Change Summary (Sessions 1–5)

| Session | Changes | Tests Added |
|---|---|---|
| 1 | `utils.sh` library, `createTakCerts.sh` rewrite, shell script hardening, `TAKServerPS` module (44 cmdlets), `TAKInstall` module (6 cmdlets), CI workflow, `Sync-TXTMirrors.ps1` | 179 |
| 2 | `TAKInstall.psd1` ReleaseNotes fix, `Connect-TAKServer.ps1` probe endpoint fix, manifests | 0 |
| 3 | `RL9_tak5.7r8_install.sh` hardening, `promoteAdmin.sh` hardening, `Invoke-TAKRequest` retry + AutoPage, `Remove-TAKUser -AlsoRevokeCertificates`, `takserver_createLECerts.sh` printf fix, stale spec removal, channels-README, 4 new test files | +46 (→ 225) |
| 4 | `takserver_createLECerts.sh` chown root:root, `openfire_takChat_install.sh` SHA256 default | 0 |
| 5 | `Remove-CivTAK.ps1` cert store cleanup fix + `-CAName` parameter | 0 |

**Total test count: 225 (160 TAKServerPS + 65 TAKInstall), 0 failures.**
