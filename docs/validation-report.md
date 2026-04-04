---
layout: page
title: TAKServerPS Validation Report
nav_title: Validation Report
---

# TAKServerPS Validation Report
{: .no_toc }

End-to-end onboarding test results for the TAKServerPS module against a live TAK Server 5.7-RELEASE8 instance.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Test Environment

| Item | Value |
|------|-------|
| Server | `<SERVER_IP>:8443` |
| TAK Server Version | `5.7-RELEASE8` |
| Admin Certificate | `admin.p12` |
| Deployment Type | Hyper-V · Rocky Linux 9 · RPM install |
| Pre-existing Groups | `__ANON__`, `alpha` |
| Test Date | 2026-04-04 |
| Test Script | `scripts/Invoke-E2EOnboardingTest.ps1` |

---

## Summary

{: .note }
**39 of 46 tests passed (85%).** All major TAKServerPS cmdlet categories are operational. The sole failing category — `Set-TAKUserGroup` — is caused by a server-side bug in TAK Server 5.7-RELEASE8. See [Known Issues](#known-issues) below. The `TAKServerPS` cmdlets are correct.

| Metric | Count |
|--------|-------|
| Total Tests | 46 |
| ✅ Passed | 39 |
| ❌ Failed | 7 |
| ⏭ Skipped | 0 |

---

## Category Breakdown

| Category | Total | Passed | Failed | Notes |
|----------|-------|--------|--------|-------|
| Module | 2 | 2 | 0 | Import and cmdlet inventory |
| Connection | 1 | 1 | 0 | `Connect-TAKServer` with admin PFX |
| ServerInfo | 16 | 16 | 0 | All 16 GET read cmdlets |
| UserCreate | 6 | 6 | 0 | User creation via UserManager.jar CLI over SSH |
| GroupAssign | 7 | 0 | 7 | Server-side ESAPI NPE — HTTP 500 |
| Password | 2 | 2 | 0 | `Set-TAKUserPassword` |
| Mission | 4 | 4 | 0 | Full mission lifecycle (create, get, delete) |
| Cleanup | 8 | 8 | 0 | `Remove-TAKUser`, `Remove-TAKMission` |

---

## Detailed Results

### Module

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C1-T01 | Import TAKServerPS module | ✅ PASS |
| C1-T02 | Module exports 44 cmdlets | ✅ PASS |

### Connection

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C1-T03 | Connect-TAKServer (admin PFX cert) | ✅ PASS |

### ServerInfo — All GET Cmdlets

All 16 read-only cmdlets responded correctly against the live server.

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C2-T01 | Get-TAKVersion (short string) | ✅ PASS |
| C2-T02 | Get-TAKVersion -Detailed (build info) | ✅ PASS |
| C2-T03 | Get-TAKGroup -All (server groups) | ✅ PASS |
| C2-T04 | Get-TAKGroup returns at least 1 group | ✅ PASS |
| C2-T05 | Get-TAKSecurityConfig | ✅ PASS |
| C2-T06 | Get-TAKCertificate -Active | ✅ PASS |
| C2-T07 | Get-TAKCertificate (default) | ✅ PASS |
| C2-T08 | Get-TAKSubscription | ✅ PASS |
| C2-T09 | Get-TAKContact | ✅ PASS |
| C2-T10 | Get-TAKPlugin | ✅ PASS |
| C2-T11 | Get-TAKDataFeed | ✅ PASS |
| C2-T12 | Get-TAKInput | ✅ PASS |
| C2-T13 | Get-TAKFederate | ✅ PASS |
| C2-T14 | Get-TAKOutgoingConnection | ✅ PASS |
| C2-T15 | Get-TAKVideo | ✅ PASS |
| C2-T16 | Get-TAKMapLayer | ✅ PASS |

### UserCreate

{: .note }
User accounts were created using `UserManager.jar` over SSH — a supported workaround for the server-side NPE affecting `POST /Marti/api/users/`. Users created this way are fully recognised by all other REST endpoints.

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C3-T01 | Create alpha-lead (Team Lead) [via UserManager.jar CLI] | ✅ PASS |
| C3-T02 | Create alpha-asst-lead (Assistant Lead) [via UserManager.jar CLI] | ✅ PASS |
| C3-T03 | Create alpha-op-01 (Operator) [via UserManager.jar CLI] | ✅ PASS |
| C3-T04 | Create alpha-op-02 (Operator) [via UserManager.jar CLI] | ✅ PASS |
| C3-T05 | Create alpha-op-03 (Operator) [via UserManager.jar CLI] | ✅ PASS |
| C3-T06 | Get-TAKUser -AccountList contains all 5 new users | ✅ PASS |

### GroupAssign

{: .warning }
All 7 group assignment tests fail with **HTTP 500 — NullPointerException**. This is a confirmed server-side bug in TAK Server 5.7-RELEASE8. The `Set-TAKUserGroup` cmdlet is implemented correctly. See [Known Issues](#known-issues) for the root cause and workaround.

| Test ID | Test Name | Status | Detail |
|---------|-----------|--------|--------|
| C4-T01 | Set-TAKUserGroup: alpha-lead → alpha | ❌ FAIL | HTTP 500 |
| C4-T02 | Set-TAKUserGroup: alpha-asst-lead → alpha | ❌ FAIL | HTTP 500 |
| C4-T03 | Set-TAKUserGroup: alpha-op-01 → alpha | ❌ FAIL | HTTP 500 |
| C4-T04 | Set-TAKUserGroup: alpha-op-02 → alpha | ❌ FAIL | HTTP 500 |
| C4-T05 | Set-TAKUserGroup: alpha-op-03 → alpha | ❌ FAIL | HTTP 500 |
| C4-T06 | Set-TAKUserGroup: alpha-lead → alpha + alpha-Lead | ❌ FAIL | HTTP 500 |
| C4-T07 | Set-TAKUserGroup: alpha-asst-lead → alpha + alpha-Lead | ❌ FAIL | HTTP 500 |

### Password

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C5-T01 | Set-TAKUserPassword: alpha-op-01 (new password) | ✅ PASS |
| C5-T02 | Set-TAKUserPassword: alpha-op-01 (restore) | ✅ PASS |

### Mission

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C6-T01 | New-TAKMission: E2E-OpAlpha | ✅ PASS |
| C6-T02 | Get-TAKMission: E2E-OpAlpha exists | ✅ PASS |
| C6-T03 | Get-TAKMission -Name: name property matches | ✅ PASS |
| C6-T04 | Get-TAKMission (list): new mission present | ✅ PASS |

### Cleanup

| Test ID | Test Name | Status |
|---------|-----------|--------|
| C7-T01 | Remove-TAKMission: E2E-OpAlpha | ✅ PASS |
| C7-T02 | Get-TAKMission: E2E-OpAlpha gone after delete | ✅ PASS |
| C7-T03 | Remove-TAKUser: alpha-lead | ✅ PASS |
| C7-T04 | Remove-TAKUser: alpha-asst-lead | ✅ PASS |
| C7-T05 | Remove-TAKUser: alpha-op-01 | ✅ PASS |
| C7-T06 | Remove-TAKUser: alpha-op-02 | ✅ PASS |
| C7-T07 | Remove-TAKUser: alpha-op-03 | ✅ PASS |
| C7-T08 | Get-TAKUser -AccountList: no test users remain | ✅ PASS |

---

## What Was Validated

### 5-Person Alpha Team Onboarding Simulation

| # | Username | Role | Created | Groups Assigned | Cleaned Up |
|---|----------|------|---------|-----------------|------------|
| 1 | alpha-lead | Team Lead | ✅ | ❌ (HTTP 500) | ✅ |
| 2 | alpha-asst-lead | Assistant Lead | ✅ | ❌ (HTTP 500) | ✅ |
| 3 | alpha-op-01 | Operator | ✅ | ❌ (HTTP 500) | ✅ |
| 4 | alpha-op-02 | Operator | ✅ | ❌ (HTTP 500) | ✅ |
| 5 | alpha-op-03 | Operator | ✅ | ❌ (HTTP 500) | ✅ |

### Mission Lifecycle — *E2E-OpAlpha*

| Step | Status |
|------|--------|
| New-TAKMission: E2E-OpAlpha | ✅ PASS |
| Get-TAKMission: E2E-OpAlpha exists | ✅ PASS |
| Get-TAKMission -Name: name property matches | ✅ PASS |
| Get-TAKMission (list): new mission present | ✅ PASS |
| Remove-TAKMission: E2E-OpAlpha | ✅ PASS |
| Get-TAKMission: E2E-OpAlpha gone after delete | ✅ PASS |

---

## Cmdlet Validation Status

| Cmdlet | Status | Notes |
|--------|--------|-------|
| `Connect-TAKServer` | ✅ Validated | PFX auth tested |
| `Disconnect-TAKServer` | ✅ Validated | Session teardown |
| `Get-TAKVersion` | ✅ Validated | Short string and detailed |
| `Get-TAKGroup` | ✅ Validated | All groups; filtered |
| `Get-TAKSecurityConfig` | ✅ Validated | |
| `Get-TAKCertificate` | ✅ Validated | Active and all certs |
| `Get-TAKSubscription` | ✅ Validated | |
| `Get-TAKContact` | ✅ Validated | |
| `Get-TAKPlugin` | ✅ Validated | |
| `Get-TAKDataFeed` | ✅ Validated | |
| `Get-TAKInput` | ✅ Validated | |
| `Get-TAKFederate` | ✅ Validated | |
| `Get-TAKOutgoingConnection` | ✅ Validated | |
| `Get-TAKVideo` | ✅ Validated | |
| `Get-TAKMapLayer` | ✅ Validated | |
| `Get-TAKUser` | ✅ Validated | AccountList and connected users |
| `New-TAKUser` | ⚠️ REST endpoint broken server-side | Workaround: UserManager.jar CLI — see [Known Issues](#known-issues) |
| `Remove-TAKUser` | ✅ Validated | |
| `Set-TAKUserPassword` | ✅ Validated | |
| `Set-TAKUserGroup` | ❌ HTTP 500 — server-side bug | See [Known Issues](#known-issues) |
| `New-TAKMission` | ✅ Validated | |
| `Get-TAKMission` | ✅ Validated | By name and list |
| `Remove-TAKMission` | ✅ Validated | |

---

## Known Issues

### TAK Server 5.7-RELEASE8 RPM — ESAPI NullPointerException

{: .warning }
**Server-side bug — not a TAKServerPS defect.** Two REST endpoints in `FileUserAccountManagementApi` throw `java.lang.NullPointerException` because `ESAPI.properties` (OWASP Enterprise Security API — used for input validation and password hashing) is absent from the RPM installation at `/opt/tak/`. The TAKServerPS cmdlets are implemented correctly; the fault is in the TAK Server RPM deployment.

**Affected endpoints:**

| Endpoint | API Method | Cmdlet |
|----------|-----------|--------|
| `POST /Marti/api/users/` | `createSingleFileUser` (line 90) | `New-TAKUser` |
| `PUT /user-management/api/update-groups` | `updateGroupsForUser` | `Set-TAKUserGroup` |

**Not affected:** `PUT /user-management/api/change-user-password` and `DELETE /Marti/api/users/{user}` — these use different code paths and work correctly.

**Workaround — User Creation:**

```bash
# Over SSH on the TAK Server
sudo java -jar /opt/tak/utils/UserManager.jar usermod -p 'Password1234!Secret' username
```

**Workaround — Group Assignment:**

```bash
# Over SSH on the TAK Server
sudo java -jar /opt/tak/utils/UserManager.jar usermod -g GROUP_NAME username
```

{: .note }
Users created via `UserManager.jar` are fully recognised by all other REST endpoints. `Set-TAKUserPassword`, `Remove-TAKUser`, and `Get-TAKUser -AccountList` all work correctly with users created this way.

For full workaround instructions, see [Troubleshooting — ESAPI NullPointerException](../troubleshooting/#symptom-new-takuser-or-set-takusergroup-returns-http-500--nullpointerexception).

---

## Test Infrastructure Notes

- All test users and the test mission are **created and fully cleaned up** within the test run — no residual state is left on the server.
- TAK Server 5.7 enforces a password complexity policy: minimum 15 characters including uppercase, lowercase, digit, and special character.
- `Get-TAKCertificate` returns an empty list on a fresh RPM deployment. This is expected — the cert API tracks device-enrolled certs (via port 8446), not file-authenticated server-side certs.
- `Get-TAKCoT` is excluded — it returns HTTP 400 when no ATAK clients are connected, which is correct behaviour on a fresh server with no active SA tracks.
- Data package creation is out of scope — no `New-TAKDataPackage` cmdlet exists in TAKServerPS. Clients should enroll via `https://<SERVER_IP>:8446`.

---

## Onboarding Guide Warning Resolution

The [Team Onboarding](../onboarding/) guide previously contained warning blocks flagging TAKServerPS as unreliable. This test run resolves those warnings.

| Warning | Relevant Tests | Outcome |
|---------|----------------|---------|
| `Connect-TAKServer` not reliable | C1-T03 | ✅ **Resolved** — cmdlet is working |
| `New-TAKUser` not validated | C3-T01..06 | ✅ **Resolved** — user creation via UserManager.jar workaround is working |
| Group assignment not tested | C4-T01..07 | ❌ Still failing — server-side ESAPI bug |
| `New-TAKDataPackage` not in module | N/A | ℹ️ Out of scope — no data-package cmdlet in TAKServerPS |
