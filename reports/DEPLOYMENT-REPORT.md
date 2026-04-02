# TAK Server Deployment Report

**Generated:** 2026-04-01 23:43:01
**Duration:** 00:12:41
**Result:** ALL TESTS PASSED

---

## Environment

| Item | Value |
|------|-------|
| VM Name | TAKServer |
| VM IP | 10.10.0.138 |
| SSH User | atak |
| OS | Rocky Linux release 9.7 (Blue Onyx) |
| Java | openjdk version "17.0.18" 2026-01-20 LTS |
| TAK Server | takserver-5.7-RELEASE8.noarch |
| Total Memory | 7.5Gi |
| Disk Usage (/) | /dev/mapper/rl_takserver-root   48G  4.0G   44G   9% / |
| Uptime | up 7 minutes |
| Hyper-V Generation | 2 |
| vCPU | 4 |
| RAM | 8 GB (fixed) |
| VHD | 80 GB (dynamic VHDX) |
| vSwitch | TAK-External |

## Certificate Configuration

| Field | Value |
|-------|-------|
| State | ESSEX |
| City | SOUTHEND-ON-SEA |
| Organization | LEIGH-SERVICES |
| OU | IT-DEPARTMENT |
| CA Name | TAK-CA |

## Credentials

| Item | Value |
|------|-------|
| SSH user | atak |
| SSH user password | romeOfed.3742 |
| Root password | romeOfed.3742 |
| Deployment keystore password parameter | romeOfed.3742 |
| Generated PKCS#12 / PFX password | atakatak |

Notes:

- The Windows-imported certificate files use the generated PKCS#12 password `atakatak`.
- This applies to `admin.p12`, `user.p12`, and `truststore-intermediate-ca.p12`.
- The deployment script may use a different `-KeystorePassword` value for server-side configuration, but the generated PKCS#12 files retain the upstream default password unless the certificate generation workflow is changed.

## Deployment Commands

PowerShell commands used to start the deployment:

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'
$cred = [PSCredential]::new('atak', (ConvertTo-SecureString 'romeOfed.3742' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString 'romeOfed.3742' -AsPlainText -Force
$ksPw = ConvertTo-SecureString 'romeOfed.3742' -AsPlainText -Force
.\\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -Confirm:$false -State 'ESSEX' -City 'SOUTHEND-ON-SEA' -Organization 'LEIGH-SERVICES' -OrganizationalUnit 'IT-DEPARTMENT' -CAName 'TAK-CA'
```

Resume runs used the same credential material and called the same script after restoring the relevant Hyper-V snapshot.

## Installation Phases

| Phase | Result | Duration |
|-------|--------|----------|
| Install TAK Server | Success | 03:28 |
| Create Certificates | Success | 01:55 |
| Promote Admin Cert | Success | 01:12 |

## Post-Deployment Test Results

**22 / 22 tests passed**

| # | Test | Result |
|---|------|--------|
| 1 | takserver service is active | :white_check_mark: PASS |
| 2 | takserver service is enabled | :white_check_mark: PASS |
| 3 | Java 17 is installed | :white_check_mark: PASS |
| 4 | PostgreSQL is running | :white_check_mark: PASS |
| 5 | Port 8089 listening (CoT) | :white_check_mark: PASS |
| 6 | Port 8443 listening (WebTAK) | :white_check_mark: PASS |
| 7 | Port 8446 listening (Cert enrollment) | :white_check_mark: PASS |
| 8 | firewalld is active | :white_check_mark: PASS |
| 9 | Firewall has 8089/tcp open | :white_check_mark: PASS |
| 10 | Firewall has 8443/tcp open | :white_check_mark: PASS |
| 11 | Firewall has 8446/tcp open | :white_check_mark: PASS |
| 12 | SELinux takserver module loaded | :white_check_mark: PASS |
| 13 | CoreConfig.xml exists | :white_check_mark: PASS |
| 14 | CA truststore exists | :white_check_mark: PASS |
| 15 | Server certificate exists | :white_check_mark: PASS |
| 16 | Admin .p12 cert exists | :white_check_mark: PASS |
| 17 | Admin .p12 in /home/atak/ | :white_check_mark: PASS |
| 18 | Certificate enrollment HTTPS responds on 8446 | :white_check_mark: PASS |
| 19 | cert-metadata.sh has correct State | :white_check_mark: PASS |
| 20 | TAK Server RPM installed | :white_check_mark: PASS |
| 21 | nofile ulimit configured | :white_check_mark: PASS |
| 22 | OS is Rocky Linux 9 | :white_check_mark: PASS |

## Access URLs

| Service | URL |
|---------|-----|
| WebTAK / Admin UI | https://10.10.0.138:8443 |
| Cursor-on-Target (CoT) | 10.10.0.138:8089 (TLS) |
| Certificate Enrollment | https://10.10.0.138:8446 |

## Next Steps

1. Retrieve `/home/atak/admin.p12` from the server and import it into your browser.
2. Navigate to `https://10.10.0.138:8443` to access the TAK Server admin UI.
3. To create user certificates, SSH to the server and run:
   ```bash
   cd /opt/tak/certs
   sudo -u tak ./takUserCreateCerts_doNotRunAsRoot.sh <username>
   ```
4. Distribute the generated `.p12` files to ATAK/WinTAK clients.
