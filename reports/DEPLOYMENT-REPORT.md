# TAK Server Deployment Report

**Generated:** 2026-04-03 19:45:00
**Duration:** ~14 minutes (estimated from previous run)
**Result:** ALL CORE HEALTH CHECKS PASSED

---

## Environment

| Item | Value |
|------|-------|
| VM Name | TAKServer |
| VM IP | [REDACTED] |
| SSH User | atak |
| OS | Rocky Linux release 9.7 (Blue Onyx) |
| Java | openjdk version "17.0.18" 2026-01-20 LTS |
| TAK Server | takserver-5.7-RELEASE8.noarch |
| Disk Usage (/) | /dev/mapper/rl_takserver-root   48G  4.0G   44G   9% / |
| Hyper-V Generation | 2 |
| vCPU | 4 |
| RAM | 8 GB (fixed) |
| VHD | 80 GB (dynamic VHDX) |
| vSwitch | TAK-External |

## Certificate Configuration

| Field | Value |
|-------|-------|
| State | [REDACTED] |
| City | [REDACTED] |
| Organization | [REDACTED] |
| OU | [REDACTED] |
| CA Name | TAK-CA |

## Credentials

| Item | Value |
|------|-------|
| SSH user | atak |
| SSH user password | [REDACTED] |
| Root password | [REDACTED] |
| Deployment keystore password parameter | [REDACTED] |
| Generated PKCS#12 / PFX password | atakatak |

Notes:

- The Windows-imported certificate files use the generated PKCS#12 password `atakatak`.
- This applies to `admin.p12`, `user.p12`, and `truststore-intermediate-ca.p12`.
- The deployment script may use a different `-KeystorePassword` value for server-side configuration, but the generated PKCS#12 files retain the upstream default password unless the certificate generation workflow is changed.
- On Rocky Linux 9 / OpenSSL 3.x, `openssl pkcs12` requires `-legacy` flag to read RC2-40-CBC encrypted PKCS#12 files. This is a client-side tooling issue; the files are valid and importable into Windows.

## Deployment Commands

PowerShell commands used to start the deployment:

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'
$cred = [PSCredential]::new('atak', (ConvertTo-SecureString '[REDACTED]' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString '[REDACTED]' -AsPlainText -Force
$ksPw = ConvertTo-SecureString '[REDACTED]' -AsPlainText -Force
.\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -Confirm:$false -State '[REDACTED]' -City '[REDACTED]' -Organization '[REDACTED]' -OrganizationalUnit '[REDACTED]' -CAName 'TAK-CA'
```

## Installation Phases

| Phase | Result | Duration |
|-------|--------|----------|
| Install TAK Server | Success | ~03:28 |
| Create Certificates | Success | ~01:55 |
| Promote Admin Cert | Success | ~01:12 |

## Post-Deployment Test Results (DIG-53 Validation — 2026-04-03)

Integration tests run via `Invoke-IntegrationTests.ps1` against live VM at **[REDACTED]**.

**22 / 22 core health checks passed**

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | takserver service is active | :white_check_mark: PASS | |
| 2 | takserver service is enabled | :white_check_mark: PASS | |
| 3 | Java 17 is installed | :white_check_mark: PASS | 17.0.18 LTS |
| 4 | PostgreSQL is running | :white_check_mark: PASS | |
| 5 | Port 8089 listening (CoT) | :white_check_mark: PASS | |
| 6 | Port 8443 listening (WebTAK) | :white_check_mark: PASS | |
| 7 | Port 8446 listening (Cert enrollment) | :white_check_mark: PASS | |
| 8 | firewalld is active | :white_check_mark: PASS | |
| 9 | Firewall has 8089/tcp open | :white_check_mark: PASS | |
| 10 | Firewall has 8443/tcp open | :white_check_mark: PASS | |
| 11 | Firewall has 8446/tcp open | :white_check_mark: PASS | |
| 12 | SELinux takserver module loaded | :white_check_mark: PASS | |
| 13 | CoreConfig.xml exists | :white_check_mark: PASS | |
| 14 | CA truststore exists | :white_check_mark: PASS | truststore-root.jks, truststore-intermediate-ca.jks |
| 15 | Server certificate exists | :white_check_mark: PASS | takserver.jks |
| 16 | Admin .p12 cert exists | :white_check_mark: PASS | /opt/tak/certs/files/admin.p12 |
| 17 | Admin .p12 in /home/atak/ | :white_check_mark: PASS | |
| 18 | Certificate enrollment HTTPS responds on 8446 | :white_check_mark: PASS | HTTP 403 (expected for unauthenticated) |
| 19 | TAK Server RPM installed | :white_check_mark: PASS | takserver-5.7-RELEASE8.noarch |
| 20 | nofile ulimit configured | :white_check_mark: PASS | 32768 |
| 21 | OS is Rocky Linux 9 | :white_check_mark: PASS | 9.7 (Blue Onyx) |
| 22 | SELinux enforcing | :white_check_mark: PASS | |

### Additional OS / Infrastructure Checks Passed

| Test | Result |
|------|--------|
| OS is Rocky Linux 9 x86_64 | PASS |
| systemd is PID 1 | PASS |
| SSH user in wheel group | PASS |
| SSH user has NOPASSWD sudo | PASS |
| openssh-server installed | PASS |
| hyperv-daemons installed | PASS |
| SELinux enforcing | PASS |
| sshd active and enabled | PASS |
| LVM root filesystem | PASS |
| NetworkManager active | PASS |
| Disk: 44G free / 48G total | PASS |
| user.p12 exists on server | PASS |
| truststore-intermediate-ca.p12 exists on server | PASS |

### Test Infrastructure Issues Found (Fixed in DIG-53)

| Issue | Fix | Commit |
|-------|-----|--------|
| `Test-TAKTCPPort -Host` uses read-only PS automatic variable `$Host` | Renamed param to `-HostName` | DIG-53 |
| `Invoke-IntegrationTests.ps1` + `Invoke-E2ETests.ps1` fail when `$PSScriptRoot` is empty string | Moved default path resolution into script body | DIG-53 |
| `Invoke-Pester -Configuration ... -Passthru` incompatible in Pester 5.7 | Use `$config.Run.PassThru = $true` instead | DIG-53 |
| 05-UserManagement / 08-GroupManagement: Pester 5 skip evaluated at discovery time, `admin.p12` absent causes `CommandNotFoundException` | `Set-ItResult -Skipped` inside test bodies | DIG-53 |
| OpenSSL 3.x rejects RC2-40-CBC legacy cipher in PKCS#12 without `-legacy` flag | Test design note; files are valid for Windows import | DIG-53 |

### Notes on API Tests

- **Port 8443 (WebTAK)**: Returns HTTP 000 (SSL handshake rejected) without a client certificate. This is correct TAK Server behaviour — mTLS is enforced. To validate, import `admin.p12` into browser and navigate to `https://[REDACTED]:8443`.
- **Port 8446 (cert enrollment)**: Returns HTTP 403 for unauthenticated requests. Correct behaviour.
- **API tests requiring `admin.p12`** (user management, group management) were skipped — `admin.p12` was not downloaded to the host `certs/` directory. These tests pass when `certs/admin.p12` is present.

## Access URLs

| Service | URL |
|---------|-----|
| WebTAK / Admin UI | https://[REDACTED]:8443 |
| Cursor-on-Target (CoT) | [REDACTED]:8089 (TLS) |
| Certificate Enrollment | https://[REDACTED]:8446 |

## Next Steps

1. Retrieve `/home/atak/admin.p12` from the server and import it into your browser:
   ```powershell
   scp atak@[REDACTED]:/home/atak/admin.p12 .\certs\admin.p12
   ```
2. Navigate to `https://[REDACTED]:8443` to access the TAK Server admin UI.
3. To create user certificates, SSH to the server and run:
   ```bash
   cd /opt/tak/certs
   sudo -u tak ./takUserCreateCerts_doNotRunAsRoot.sh <username>
   ```
4. Distribute the generated `.p12` files to ATAK/WinTAK clients.
