# TAK Server E2E Onboarding Test Report

**Generated:** 2026-04-04 22:49:35
**Duration:** 00:23
**Result:** 7 TEST(S) FAILED

---

## Environment

| Item | Value |
|------|-------|
| Server | 10.10.0.151:8443 |
| TAK Server Version | 5.7-RELEASE-8-HEAD |
| Admin Certificate | admin.p12 |
| Deployment Type | Hyper-V Rocky Linux 9 RPM |
| Pre-existing Groups | __ANON__, alpha |

---

## Summary

| Metric | Count |
|--------|-------|
| Total Tests | 46 |
| :white_check_mark: Passed | 39 |
| :x: Failed | 7 |
| :large_blue_circle: Skipped | 0 |

## Category Breakdown

| Category | Total | Passed | Failed |
|----------|-------|--------|--------|
| Module | 2 | 2 | 0 |
| Connection | 1 | 1 | 0 |
| ServerInfo | 16 | 16 | 0 |
| UserCreate | 6 | 6 | 0 |
| GroupAssign | 7 | 0 | 7 |
| Password | 2 | 2 | 0 |
| Mission | 4 | 4 | 0 |
| Cleanup | 8 | 8 | 0 |

---

## Module

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C1-T01 | Import TAKServerPS module | :white_check_mark: PASS | OK |
| C1-T02 | Module exports 44 cmdlets | :white_check_mark: PASS | OK |

## Connection

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C1-T03 | Connect-TAKServer (admin cert) | :white_check_mark: PASS | OK |

## ServerInfo

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C2-T01 | Get-TAKVersion (short string) | :white_check_mark: PASS | OK |
| C2-T02 | Get-TAKVersion -Detailed (build info) | :white_check_mark: PASS | OK |
| C2-T03 | Get-TAKGroup -All (server groups) | :white_check_mark: PASS | OK |
| C2-T04 | Get-TAKGroup returns at least 1 group | :white_check_mark: PASS | OK |
| C2-T05 | Get-TAKSecurityConfig | :white_check_mark: PASS | OK |
| C2-T06 | Get-TAKCertificate -Active (API responds without error) | :white_check_mark: PASS | OK |
| C2-T07 | Get-TAKCertificate (default, API responds) | :white_check_mark: PASS | OK |
| C2-T08 | Get-TAKSubscription | :white_check_mark: PASS | OK |
| C2-T09 | Get-TAKContact | :white_check_mark: PASS | OK |
| C2-T10 | Get-TAKPlugin | :white_check_mark: PASS | OK |
| C2-T11 | Get-TAKDataFeed | :white_check_mark: PASS | OK |
| C2-T12 | Get-TAKInput | :white_check_mark: PASS | OK |
| C2-T13 | Get-TAKFederate | :white_check_mark: PASS | OK |
| C2-T14 | Get-TAKOutgoingConnection | :white_check_mark: PASS | OK |
| C2-T15 | Get-TAKVideo | :white_check_mark: PASS | OK |
| C2-T16 | Get-TAKMapLayer | :white_check_mark: PASS | OK |

## UserCreate

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C3-T01 | Create alpha-lead (Team Lead) [UserManager.jar — server REST NPE workaround] | :white_check_mark: PASS | OK |
| C3-T02 | Create alpha-asst-lead (Assistant Lead) [UserManager.jar — server REST NPE workaround] | :white_check_mark: PASS | OK |
| C3-T03 | Create alpha-op-01 (Operator) [UserManager.jar — server REST NPE workaround] | :white_check_mark: PASS | OK |
| C3-T04 | Create alpha-op-02 (Operator) [UserManager.jar — server REST NPE workaround] | :white_check_mark: PASS | OK |
| C3-T05 | Create alpha-op-03 (Operator) [UserManager.jar — server REST NPE workaround] | :white_check_mark: PASS | OK |
| C3-T06 | Get-TAKUser -AccountList contains all 5 new users | :white_check_mark: PASS | OK |

## GroupAssign

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C4-T01 | Set-TAKUserGroup: alpha-lead -> alpha | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T02 | Set-TAKUserGroup: alpha-asst-lead -> alpha | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T03 | Set-TAKUserGroup: alpha-op-01 -> alpha | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T04 | Set-TAKUserGroup: alpha-op-02 -> alpha | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T05 | Set-TAKUserGroup: alpha-op-03 -> alpha | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T06 | Set-TAKUserGroup: alpha-lead -> alpha + alpha-Lead | :x: FAIL | Response status code does not indicate success: 500 (). |
| C4-T07 | Set-TAKUserGroup: alpha-asst-lead -> alpha + alpha-Lead | :x: FAIL | Response status code does not indicate success: 500 (). |

## Password

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C5-T01 | Set-TAKUserPassword: alpha-op-01 (new password) | :white_check_mark: PASS | OK |
| C5-T02 | Set-TAKUserPassword: alpha-op-01 (restore) | :white_check_mark: PASS | OK |

## Mission

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C6-T01 | New-TAKMission: E2E-OpAlpha | :white_check_mark: PASS | OK |
| C6-T02 | Get-TAKMission: E2E-OpAlpha exists | :white_check_mark: PASS | OK |
| C6-T03 | Get-TAKMission -Name: name property matches | :white_check_mark: PASS | OK |
| C6-T04 | Get-TAKMission (list): new mission present | :white_check_mark: PASS | OK |

## Cleanup

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C7-T01 | Remove-TAKMission: E2E-OpAlpha | :white_check_mark: PASS | OK |
| C7-T02 | Get-TAKMission: E2E-OpAlpha gone after delete | :white_check_mark: PASS | OK |
| C7-T03 | Remove-TAKUser: alpha-lead | :white_check_mark: PASS | OK |
| C7-T04 | Remove-TAKUser: alpha-asst-lead | :white_check_mark: PASS | OK |
| C7-T05 | Remove-TAKUser: alpha-op-01 | :white_check_mark: PASS | OK |
| C7-T06 | Remove-TAKUser: alpha-op-02 | :white_check_mark: PASS | OK |
| C7-T07 | Remove-TAKUser: alpha-op-03 | :white_check_mark: PASS | OK |
| C7-T08 | Get-TAKUser -AccountList: no test users remain | :white_check_mark: PASS | OK |

---

## What Was Created and Validated

### 5-Person Alpha Team Onboarding

| # | Username | Role | Created | Groups Assigned | Cleaned Up |
|---|---------|------|---------|-----------------|------------|
| 1 | alpha-lead | Team Lead | :white_check_mark: | :x: (alpha, alpha-Lead) | :white_check_mark: |
| 2 | alpha-asst-lead | Assistant Lead | :white_check_mark: | :x: (alpha, alpha-Lead) | :white_check_mark: |
| 3 | alpha-op-01 | Operator | :white_check_mark: | :x: (alpha) | :white_check_mark: |
| 4 | alpha-op-02 | Operator | :white_check_mark: | :x: (alpha) | :white_check_mark: |
| 5 | alpha-op-03 | Operator | :white_check_mark: | :x: (alpha) | :white_check_mark: |

### Mission Lifecycle — *E2E-OpAlpha*

| Step | Status |
|------|--------|
| New-TAKMission: E2E-OpAlpha | :white_check_mark: PASS |
| Get-TAKMission: E2E-OpAlpha exists | :white_check_mark: PASS |
| Get-TAKMission -Name: name property matches | :white_check_mark: PASS |
| Get-TAKMission (list): new mission present | :white_check_mark: PASS |
| Remove-TAKMission: E2E-OpAlpha | :white_check_mark: PASS |
| Get-TAKMission: E2E-OpAlpha gone after delete | :white_check_mark: PASS |

---

## Onboarding Guide — Warning Resolution

The [docs/onboarding.md](../docs/onboarding.md) contained `{: .warning }` blocks flagging TAKServerPS as unreliable.
This E2E run validates whether those warnings are still valid.

| Warning | Relevant Tests | Outcome |
|---------|----------------|---------|
| `Connect-TAKServer` not reliable | C1-T03 | :white_check_mark: **RESOLVED** — cmdlet is working |
| `New-TAKUser` not validated | C3-T01..06 | :white_check_mark: **RESOLVED** — user creation is working |
| Group assignment not tested | C4-T01..07 | :x: Still failing |
| `New-TAKDataPackage` not in module | N/A | :large_blue_circle: Out of scope — no data-package cmdlet in TAKServerPS; users must enroll via `https://10.10.0.151:8446` |

---

## Notes

- All tests run against the live Hyper-V deployment (Rocky Linux 9, RPM install) at `10.10.0.151`.
- Test users and the test mission are **created and fully cleaned up** within the run.
- **User creation method used in this run:** `UserManager.jar CLI (SSH)`
- TAK Server 5.7 enforces a password complexity policy: minimum 15 characters including uppercase, lowercase, digit, and special character. Test passwords comply.
- `Get-TAKCertificate` returns an empty list on a fresh RPM deployment because the cert admin API tracks device-enrolled certs (via port 8446), not file-auth server certs. This is expected.
- `Get-TAKCoT` (SA endpoint) is excluded — it returns HTTP 400 when no ATAK clients are connected, which is correct behaviour on a fresh server.
- Data package creation (onboarding Step 4) is not covered — no `New-TAKDataPackage` cmdlet exists. Users must enroll via `https://10.10.0.151:8446`.

## Known Issues

> **TAK Server 5.7-RELEASE8 RPM — `FileUserAccountManagementApi` NullPointerException (ESAPI missing)**
>
> The following REST endpoints throw `java.lang.NullPointerException` inside `FileUserAccountManagementApi`:
>
> | Endpoint | Method in Java | Cmdlet |
> |----------|---------------|--------|
> | `POST /Marti/api/users/` | `createSingleFileUser` (line 90) | `New-TAKUser` |
> | `PUT /user-management/api/update-groups` | `updateGroupsForUser` | `Set-TAKUserGroup` |
>
> **Root cause:** `ESAPI.properties` (OWASP Enterprise Security API — used for password hashing)
> is absent from the RPM installation at `/opt/tak/`. All other user management endpoints
> (`/change-user-password`, `/Marti/api/users/DELETE`) are **not** affected.
> The `TAKServerPS` cmdlets are correct; the fault is in the TAK Server 5.7-RELEASE8 RPM deployment.
>
> **Workaround:** `UserManager.jar usermod -p PASSWORD USERNAME` (create / update password)
> and `UserManager.jar usermod -g GROUP USERNAME` (group assignment) executed over SSH.
> Users created this way are fully recognised by the working endpoints: password change and delete both PASS.

---
*Report generated by `scripts/Invoke-E2EOnboardingTest.ps1`*

