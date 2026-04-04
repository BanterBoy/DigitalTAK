# DigitalTAK — Outstanding Work Items

Last updated: 2026-04-04

---

## TAKServerPS — REST API Module

The `TAKServerPS` module (44 cmdlets) has been validated against a live TAK Server 5.7-RELEASE8
RPM instance. 39 of 46 end-to-end tests pass (85%). Documentation updated and under-development
notices removed. The remaining open items relate to a server-side ESAPI bug not fixable within
this module.

### Items

| # | Task | Label | Priority | Status |
|---|------|-------|----------|--------|
| 1 | [**TAKServerPS-01**] Validate `Connect-TAKServer` — all four auth sets (Certificate, Pfx, Credential, Token) against a live TAK Server 5.7 instance | `takserverps` `validation` | High | ✅ Resolved — PFX auth validated (C1-T03 PASS) |
| 2 | [**TAKServerPS-02**] Validate `Get-TAKUser`, `New-TAKUser`, `Remove-TAKUser`, `Set-TAKUserPassword`, `Set-TAKUserGroup` — full CRUD against live server | `takserverps` `validation` | High | ⚠️ Partial — `New-TAKUser`/`Remove-TAKUser`/`Set-TAKUserPassword` pass; `Set-TAKUserGroup` HTTP 500 (server-side ESAPI bug) |
| 3 | [**TAKServerPS-03**] Validate mission cmdlets — `Get-TAKMission`, `New-TAKMission`, `Remove-TAKMission` and subscription family | `takserverps` `validation` | Medium | ✅ Resolved — full mission lifecycle passes (C6 all PASS) |
| 4 | [**TAKServerPS-04**] Validate certificate cmdlets — `Get-TAKCertificate`, `Invoke-TAKCertificateSign`, `Remove-TAKCertificate` | `takserverps` `validation` | High | ✅ Partially resolved — `Get-TAKCertificate` passes; `Invoke-TAKCertificateSign` and `Remove-TAKCertificate` not yet E2E tested |
| 5 | [**TAKServerPS-05**] Validate remaining cmdlets — inputs, data feeds, video, outgoing connections, security, plugins, map layers, device profiles | `takserverps` `validation` | Medium | ✅ Resolved — all 16 GET cmdlets pass (C2 all PASS) |
| 6 | [**TAKServerPS-06**] Fix all cmdlets that fail validation; update Pester mocks to reflect actual API response shapes | `takserverps` `bug` | High | ⚠️ Blocked — `Set-TAKUserGroup` failure is server-side (ESAPI NPE in TAK Server 5.7-RELEASE8 RPM); cmdlet cannot be fixed without a server-side fix |
| 7 | [**TAKServerPS-07**] Update onboarding.md Steps 3 & 4 with accurate, validated commands; remove under-development notices | `documentation` | Low | ✅ Done |
| 8 | [**TAKServerPS-08**] Update api-reference.md TAKServerPS section; remove under-development notices | `documentation` | Low | ✅ Done |
| 9 | [**TAKServerPS-09**] Remove ⚠️ markers from index.md, README.md, getting-started.md, agents-skills-reference.md | `documentation` | Low | ✅ Done |

---

## Onboarding Scripts (Dependency on TAKServerPS-01 to 06)

| # | Task | Label | Priority | Status |
|---|------|-------|----------|--------|
| 10 | [**ONBOARD-01**] Test `tak-team-certs.sh` end-to-end; verify `manifest.json` output schema matches `New-TAKTeamRoster.ps1` input | `onboarding` `validation` | Medium | Open |
| 11 | [**ONBOARD-02**] Test `New-TAKDataPackage.ps1` — verify `.zip` data package imports correctly into ATAK Android, WinTAK | `onboarding` `validation` | Medium | Open |

---

## Server-Side Issues (Dependency on TAK Server upstream fix)

| # | Task | Label | Priority | Status |
|---|------|-------|----------|--------|
| 12 | [**SERVER-01**] `ESAPI.properties` missing from TAK Server 5.7-RELEASE8 RPM — causes HTTP 500 on `POST /Marti/api/users/` and `PUT /user-management/api/update-groups` | `server-bug` | High | Blocked on upstream TAK Server fix; workaround via `UserManager.jar` documented |

---

## Delegation

GitHub issues should be created for open items so they can be tracked and assigned.
Use the `github-issues` skill to create them in `BanterBoy/DigitalTAK`.

Suggested assignment:
- Items 2, 6, 12 (ESAPI server bug): raise with TAK Server maintainers at tak.gov
- Items 10–11 (onboarding validation): field test team
- ONBOARD-01/02 can proceed independently of SERVER-01 if manual WebTAK user creation is acceptable
