# DigitalTAK — Pester Test Report

**Date:** 2026-03-22  
**PowerShell:** 7.6.0  
**Pester:** 5.7.1  
**PSScriptAnalyzer:** 1.24.0  
**Platform:** Windows (VS Code)

---

## Executive Summary

All 179 tests pass across both PowerShell modules.  
Two bugs were discovered and fixed during the test run (see [Bug Fixes](#bug-fixes)).

| Module | Test Files | Tests | Passed | Failed | Result |
|--------|-----------|-------|--------|--------|--------|
| TAKServerPS | 3 | 114 | 114 | 0 | ✅ PASS |
| TAKInstall | 4 | 65 | 65 | 0 | ✅ PASS |
| **Total** | **7** | **179** | **179** | **0** | **✅ ALL PASS** |

---

## TAKServerPS Module

### TAKServerPS.Module.Tests.ps1 — 73 passed, 0 failed

Tests the module manifest, exported function inventory, and function metadata.

| Test | Result |
|------|--------|
| Module loads without error | ✅ |
| Exactly 44 functions exported | ✅ |
| All 44 exported functions present (44 individual checks) | ✅ |
| No functions use unapproved verbs | ✅ |
| All exported functions declare `[OutputType]` | ✅ |
| All exported functions have synopsis in help | ✅ |
| All exported functions declare at least one parameter | ✅ |
| Module requires PowerShell 7.0 or higher | ✅ |
| ModuleVersion is set in manifest | ✅ |
| GUID is non-empty | ✅ |
| Author field is non-empty | ✅ |

### Invoke-TAKRequest.Tests.ps1 — 22 passed, 0 failed

Tests the private `Invoke-TAKRequest` HTTP helper used by all TAKServerPS public cmdlets.

| Test | Result |
|------|--------|
| Throws `TAKNotConnected` when no session is set | ✅ |
| URI built from BaseUrl + Path | ✅ |
| Slashes are normalised (no double-slash) | ✅ |
| Certificate authentication takes priority over Token | ✅ |
| Certificate authentication takes priority over Credential | ✅ |
| Token (SecureString) is passed as Bearer header | ✅ |
| PSCredential is passed via `-Credential` parameter | ✅ |
| Method parameter is forwarded to `Invoke-RestMethod` | ✅ |
| Body parameter is forwarded to `Invoke-RestMethod` | ✅ |
| Response `.data` property is unwrapped automatically | ✅ |
| `-Raw` switch returns the full response object | ✅ |
| Null `.data` returns null (no exception) | ✅ |
| HTTP 400 response throws `TAKRequestFailed` | ✅ |
| HTTP error message includes the status code | ✅ |
| HTTP error message includes the path | ✅ |
| HTTP error message includes the response body | ✅ |
| `SkipCertificateCheck` is forwarded when session has `SkipCertCheck = $true` | ✅ |
| `SkipCertificateCheck` is NOT set when session has `SkipCertCheck = $false` | ✅ |
| ContentType defaults to `application/json` | ✅ |
| Accept header defaults to `application/json` | ✅ |
| `Invoke-RestMethod` is called exactly once per request | ✅ |
| Session BaseUrl trailing slash is handled | ✅ |

### Connect-TAKServer.Tests.ps1 — 19 passed, 0 failed

Tests the four connection parameter sets (`Certificate`, `Pfx`, `Credential`, `Token`).

| Test | Result |
|------|--------|
| Certificate parameter set creates a session with BaseUrl | ✅ |
| Certificate parameter set stores the X509Certificate2 object | ✅ |
| Pfx parameter set loads the certificate from file | ✅ |
| Pfx parameter set stores the loaded certificate on the session | ✅ |
| Credential parameter set stores the PSCredential on the session | ✅ |
| Token parameter set stores the SecureString token | ✅ |
| SkipCertificateCheck is stored on the session when supplied | ✅ |
| Session is accessible via `Get-TAKSession` after connect | ✅ |
| `Disconnect-TAKServer` clears the session | ✅ |
| Unknown host throws a connectivity error | ✅ |
| Session is cleared on connectivity failure | ✅ |
| BaseUrl is stored without trailing slash | ✅ |
| BaseUrl is stored with correct scheme | ✅ |
| Port 443 is accepted | ✅ |
| Port 8443 is accepted (TAK default) | ✅ |
| Server parameter is mandatory | ✅ |
| Certificate is mandatory in Certificate parameter set | ✅ |
| PfxPath is mandatory in Pfx parameter set | ✅ |
| Credential is mandatory in Credential parameter set | ✅ |

---

## TAKInstall Module

### TAKInstall.Module.Tests.ps1 — 31 passed, 0 failed

Tests the module manifest, exported function inventory, required modules, and function metadata.  
**Note:** This test initially failed (1 failure) due to a parse error in `New-TAKServerCertificate.ps1`; see [Bug Fix #1](#bug-fix-1--invalid-escape-sequences-in-new-takservercertificateps1).

| Test | Result |
|------|--------|
| Module loads without error | ✅ |
| Exactly 6 public functions exported | ✅ |
| All 6 exported functions present (6 individual checks) | ✅ |
| `Posh-SSH` is listed in `RequiredModules` | ✅ |
| No functions use unapproved verbs | ✅ |
| All exported functions declare `[OutputType]` | ✅ |
| All exported functions have synopsis in help | ✅ |
| All exported functions have full description in help | ✅ |
| All exported functions have at least one `.EXAMPLE` | ✅ |
| All exported functions declare `SshSession` as first mandatory parameter | ✅ |
| Module requires PowerShell 7.0 or higher | ✅ |
| ModuleVersion is set | ✅ |
| GUID is non-empty | ✅ |
| Author field is non-empty | ✅ |
| Private functions are NOT exported | ✅ |
| 3 private helpers exist and are accessible within module scope | ✅ |

### ConvertTo-TAKBashArg.Tests.ps1 — 4 passed, 0 failed

Tests the private helper that wraps values in bash single-quotes for safe expansion in remote commands.

| Test | Result |
|------|--------|
| Plain value is wrapped in single quotes | ✅ |
| Embedded single quote is escaped as `'\''` | ✅ |
| Special shell characters (`$`, `` ` ``, `!`) are preserved literally | ✅ |
| Empty string returns empty single-quoted string `''` | ✅ |

### Invoke-TAKRemoteCommand.Tests.ps1 — 16 passed, 0 failed

Tests the private SSH command executor that wraps `Invoke-SSHCommand` (Posh-SSH).  
**Note:** 2 tests required correction; see [Bug Fix #2](#bug-fix-2--verbose-capture-and-allowfailure-test-bugs).

| Test | Result |
|------|--------|
| Calls `Invoke-SSHCommand` exactly once | ✅ |
| Passes the command string to `Invoke-SSHCommand` | ✅ |
| Passes the SSH session to `Invoke-SSHCommand` | ✅ |
| Returns the result object when exit code is 0 | ✅ |
| Writes a verbose message when `Description` is supplied | ✅ |
| Throws a terminating error when exit code is non-zero | ✅ |
| Error has `ErrorId` of `TAKRemoteCommandFailed` | ✅ |
| Error message includes the exit status code | ✅ |
| Error message includes the failed command | ✅ |
| Error message includes the stderr output | ✅ |
| Error message includes `Description` when supplied | ✅ |
| Does NOT throw when `-AllowFailure` is specified | ✅ |
| Returns the result object when `-AllowFailure` is specified | ✅ |
| `Command` parameter is mandatory | ✅ |
| `Session` parameter is mandatory | ✅ |
| `AllowFailure` is a switch parameter | ✅ |

### Wait-TAKServiceReady.Tests.ps1 — 14 passed, 0 failed

Tests the private polling helper that waits for a systemd service to reach the `active (running)` state.

| Test | Result |
|------|--------|
| Returns immediately when service is already active | ✅ |
| Calls `Invoke-SSHCommand` at least once to check status | ✅ |
| Polls until the service becomes active | ✅ |
| Default service name is `takserver` | ✅ |
| Throws `TAKServiceTimeout` when service never becomes active | ✅ |
| Timeout error message includes the service name | ✅ |
| Timeout error message includes the timeout value | ✅ |
| Uses the `TimeoutSeconds` parameter | ✅ |
| Uses the `PollIntervalSeconds` parameter | ✅ |
| Calls `Write-Progress` at least once during polling | ✅ |
| `Write-Progress` activity includes the service name | ✅ |
| Completes `Write-Progress` after service becomes active | ✅ |
| `Session` parameter is mandatory | ✅ |
| `ServiceName` parameter defaults to `takserver` | ✅ |

---

## Bug Fixes

### Bug Fix 1 — Invalid escape sequences in `New-TAKServerCertificate.ps1`

**File:** `TAKInstall/Public/New-TAKServerCertificate.ps1` (lines 203–213)  
**Symptom:** Module failed to parse, causing all TAKInstall module tests to fail with `Unexpected token` errors.

**Root cause:** PowerShell uses backtick (`` ` ``) as its escape character inside double-quoted strings. Backslash (`\`) is NOT an escape character. The code had used `\"` (backslash-quote) in double-quoted strings intending to produce literal `"` characters.

**Example (before):**
```powershell
$signingBlock  = '<certificateSigning CA=\"TAKServer\">'
$signingBlock += "<TAKServerCAConfig keystore=\"JKS\" ... keystorePass=$bPass ... />"
$signingCmd    = "sudo sed -i 's|<vbm enabled=\\\"false\\\"/>|$signingBlock|g' /opt/tak/CoreConfig.xml"
```

**Example (after):**
```powershell
$signingBlock  = '<certificateSigning CA="TAKServer">'
$signingBlock += "<TAKServerCAConfig keystore=`"JKS`" ... keystorePass=$bPass ... />"
$signingCmd    = "sudo sed -i 's|<vbm enabled=`"false`"/>|$signingBlock|g' /opt/tak/CoreConfig.xml"
```

Lines without variable interpolation were switched to single-quoted strings; lines with `$bPass` use `` `" `` for embedded double-quotes.

---

### Bug Fix 2 — Verbose capture and `-AllowFailure` test bugs

**File:** `TAKInstall/Tests/Invoke-TAKRemoteCommand.Tests.ps1`

#### 2a — Verbose capture with `4>&1` inside `InModuleScope`

**Symptom:** The assertion `$verboseMessages | Should -Match 'Test step'` received only the function's return object, not the verbose record.

**Root cause:** PowerShell's `4>&1` verbose redirect does not reliably propagate `Write-Verbose` output across the `InModuleScope` scope boundary in Pester 5. The verbose preference set inside `InModuleScope` does not affect the outer capture.

**Fix:** Mock `Write-Verbose` at module scope with `Mock Write-Verbose -ModuleName TAKInstall` and assert the call with `Should -Invoke Write-Verbose -ParameterFilter { $Message -match 'Test step' }`.

#### 2b — `-AllowFailure` sentinel test

**Symptom:** The assertion `$err | Should -Be 'no-throw'` received an array `@($resultObj, 'no-throw')` instead of the scalar string.

**Root cause:** When `-AllowFailure` is set, `Invoke-TAKRemoteCommand` returns the result object to the success stream. The `try` block therefore emits both the result object and the sentinel string `'no-throw'`, making `$err` an array.

**Fix:** Added `$null = ` assignment prefix to discard the function return value: `$null = Invoke-TAKRemoteCommand ... -AllowFailure`.

---

## PSScriptAnalyzer Summary

Both modules were validated with PSScriptAnalyzer 1.24.0 prior to test execution. No errors or warnings are produced by either module (suppression attributes are applied for analysed false-positives with documented justifications).

| Module | Errors | Warnings | Information | Result |
|--------|--------|----------|-------------|--------|
| TAKServerPS | 0 | 0 | 0 | ✅ Clean |
| TAKInstall | 0 | 0 | 0 | ✅ Clean |

---

## Module Inventory

### TAKServerPS — 44 exported functions

| Function | Category |
|----------|----------|
| `Connect-TAKServer` | Session |
| `Disconnect-TAKServer` | Session |
| `Get-TAKSession` | Session |
| `Get-TAKUser` | Users |
| `New-TAKUser` | Users |
| `Remove-TAKUser` | Users |
| `Set-TAKUserPassword` | Users |
| `Get-TAKGroup` | Groups |
| `New-TAKGroup` | Groups |
| `Remove-TAKGroup` | Groups |
| `Add-TAKGroupMember` | Groups |
| `Remove-TAKGroupMember` | Groups |
| `Get-TAKChannel` | Channels |
| `New-TAKChannel` | Channels |
| `Remove-TAKChannel` | Channels |
| `Get-TAKDataPackage` | Data Packages |
| `Send-TAKDataPackage` | Data Packages |
| `Remove-TAKDataPackage` | Data Packages |
| `Get-TAKMission` | Missions |
| `New-TAKMission` | Missions |
| `Remove-TAKMission` | Missions |
| `Add-TAKMissionContent` | Missions |
| `Remove-TAKMissionContent` | Missions |
| `Get-TAKMissionSubscription` | Missions |
| `Add-TAKMissionSubscription` | Missions |
| `Remove-TAKMissionSubscription` | Missions |
| `Get-TAKCot` | CoT |
| `Send-TAKCot` | CoT |
| `Get-TAKFederation` | Federation |
| `New-TAKFederation` | Federation |
| `Remove-TAKFederation` | Federation |
| `Get-TAKFederationGroup` | Federation |
| `Add-TAKFederationGroup` | Federation |
| `Remove-TAKFederationGroup` | Federation |
| `Get-TAKCertificate` | Certificates |
| `New-TAKCertificate` | Certificates |
| `Revoke-TAKCertificate` | Certificates |
| `Get-TAKPlugin` | Plugins |
| `Enable-TAKPlugin` | Plugins |
| `Disable-TAKPlugin` | Plugins |
| `Get-TAKServerInfo` | Server |
| `Get-TAKServerConfig` | Server |
| `Set-TAKServerConfig` | Server |
| `Restart-TAKService` | Server |

### TAKInstall — 6 exported functions

| Function | Description |
|----------|-------------|
| `Install-TAKServer` | Installs TAK Server RPM, PostgreSQL, and configures firewalld on Rocky Linux 9 via SSH |
| `New-TAKServerCertificate` | Creates the Certificate Authority, server cert, and configures CoreConfig.xml for x509 auth |
| `Set-TAKAdminCertificate` | Promotes the admin client certificate to the TAK Server administrator role |
| `New-TAKUserCertificate` | Generates a per-user client certificate and exports the data package |
| `Install-OpenfireChat` | Installs Openfire XMPP and the TAK Server chat plugin |
| `Install-LetsEncryptCertificate` | Issues and configures a Let's Encrypt TLS certificate for the TAK Server HTTPS endpoint |
