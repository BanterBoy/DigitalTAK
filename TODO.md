# DigitalTAK — Outstanding Work Items

Last updated: 2026-04-04

---

## TAKServerPS — REST API Module (⚠️ Blocked on Validation)

The `TAKServerPS` module (44 cmdlets) has not been fully tested against a live TAK Server 5.7
instance. All documentation pages that reference TAKServerPS have been marked with under-development
notices. The following work items must be resolved before those notices can be removed.

### Items

| # | Task | Label | Priority |
|---|------|-------|----------|
| 1 | [**TAKServerPS-01**] Validate `Connect-TAKServer` — all four auth sets (Certificate, Pfx, Credential, Token) against a live TAK Server 5.7 instance | `takserverps` `validation` | High |
| 2 | [**TAKServerPS-02**] Validate `Get-TAKUser`, `New-TAKUser`, `Remove-TAKUser`, `Set-TAKUserPassword`, `Set-TAKUserGroup` — full CRUD against live server | `takserverps` `validation` | High |
| 3 | [**TAKServerPS-03**] Validate mission cmdlets — `Get-TAKMission`, `New-TAKMission`, `Remove-TAKMission` and subscription family | `takserverps` `validation` | Medium |
| 4 | [**TAKServerPS-04**] Validate certificate cmdlets — `Get-TAKCertificate`, `Invoke-TAKCertificateSign`, `Remove-TAKCertificate` | `takserverps` `validation` | High |
| 5 | [**TAKServerPS-05**] Validate remaining cmdlets — inputs, data feeds, video, outgoing connections, security, plugins, map layers, device profiles | `takserverps` `validation` | Medium |
| 6 | [**TAKServerPS-06**] Fix all cmdlets that fail validation; update Pester mocks to reflect actual API response shapes | `takserverps` `bug` | High |
| 7 | [**TAKServerPS-07**] Update onboarding.md Steps 3 & 4 with accurate, validated commands; remove under-development notices | `documentation` | Low (after items 1–6) |
| 8 | [**TAKServerPS-08**] Update api-reference.md TAKServerPS section; remove under-development notices | `documentation` | Low (after items 1–6) |
| 9 | [**TAKServerPS-09**] Remove ⚠️ markers from index.md, README.md, CHANGELOG.md, Docker-Deploy-Runbook.md | `documentation` | Low (after items 1–6) |

---

## Onboarding Scripts (Dependency on TAKServerPS-01 to 06)

| # | Task | Label | Priority |
|---|------|-------|----------|
| 10 | [**ONBOARD-01**] Test `tak-team-certs.sh` end-to-end; verify `manifest.json` output schema matches `New-TAKTeamRoster.ps1` input | `onboarding` `validation` | Medium |
| 11 | [**ONBOARD-02**] Test `New-TAKDataPackage.ps1` — verify `.zip` data package imports correctly into ATAK Android, WinTAK | `onboarding` `validation` | Medium |

---

## Delegation

GitHub issues should be created for items 1–9 (TAKServerPS) so they can be tracked and assigned.
Use the `github-issues` skill to create them in `BanterBoy/DigitalTAK`.

Suggested assignment:
- Items 1–6 (code validation + fixes): engineering lead / PowerShell developer
- Items 7–9 (documentation cleanup): documentation owner (after code items close)
- Items 10–11 (onboarding validation): field test team
