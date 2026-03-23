# TAK Server Deployment Report

**Date:** 2025-03-23  
**Author:** DigitalTAK Orchestrator  
**Target:** TAK Server 5.7-RELEASE8 on Rocky Linux 9 / Hyper-V Gen 2

---

## Executive Summary

A fully functional TAK Server 5.7-RELEASE8 instance was deployed on a Hyper-V Gen 2 virtual machine running Rocky Linux 9.7. The server is operational with mutual-TLS certificate authentication, SELinux enforcing, and firewalld configured. 21 of 22 post-deployment tests passed; the single expected failure is the unauthenticated HTTPS check (the server correctly requires a client certificate).

---

## Environment

| Component | Value |
|-----------|-------|
| Hypervisor | Hyper-V Gen 2, External vSwitch `TAK-External` (Intel I219-LM) |
| VM Name | `TAKServer` |
| vCPU | 4 |
| RAM | 8 GB (fixed) |
| Disk | 80 GB VHDX (dynamic) |
| OS | Rocky Linux 9.7 |
| IP Address | `10.10.0.124` |
| Java | OpenJDK 17 |
| Database | PostgreSQL (PGDG RHEL 9 repo) |
| TAK RPM | `takserver-5.7-RELEASE8.noarch` |
| SELinux | Enforcing (`takserver-policy` applied) |
| Firewall | firewalld — ports 8089, 8443, 8446 open |

### User Accounts

| User | Purpose |
|------|---------|
| `atak` | SSH admin with passwordless sudo (`/etc/sudoers.d/atak`) |
| `root` | Root account (direct SSH disabled by best practice) |

---

## Certificate Chain

All certificates were generated using the TAK Server `cert-metadata.sh` + `makeRootCa.sh` / `makeCert.sh` tooling.

### Certificate Metadata

| Field | Value |
|-------|-------|
| Country (C) | GB |
| State (ST) | ESSEX |
| City (L) | SOUTHEND-ON-SEA |
| Organization (O) | LEIGH-SERVICES |
| Organizational Unit (OU) | IT-DEPARTMENT |

### Certificate Inventory

| Certificate | CN | Type | File |
|------------|-----|------|------|
| Root CA | `TAK-CA` | Root CA | `root-ca.pem`, `truststore-root.p12` |
| Intermediate CA | `intermediate-ca` | Intermediate CA | `intermediate-ca.pem`, `truststore-intermediate-ca.p12` |
| Server | `takserver` | Server TLS | `takserver.p12` |
| Admin | `admin` | Client (ROLE_ADMIN) | `admin.p12`, `admin.pem` |
| User | `user` | Client | `user.p12`, `user.pem` |

### Admin Promotion

- **User:** admin
- **Role:** ROLE_ADMIN
- **Fingerprint:** `FA:3A:A5:B2:86:D7:FA:40:02:33:6B:93:7D:EC:03:48:44:F6:AE:DC:D5:28:52:89:8C:2A:C8:DB:80:3A:12:F8`
- **Method:** `java -jar UserManager.jar certmod -A admin.pem`

---

## CoreConfig.xml Modifications

| Change | Detail |
|--------|--------|
| Trust store | Switched from `truststore-root.jks` to `truststore-intermediate-ca.jks` |
| Certificate signing | Added `<certificateSigning>` block with `intermediate-ca-signing.jks`, validity 30 days |
| x509 group cache | Enabled `<groupCache enabled="true"/>` |
| Keystore passwords | All updated from default `atakatak` to deployment password |

---

## Network Ports

| Port | Protocol | Service | Status |
|------|----------|---------|--------|
| 8089 | TCP/TLS | Cursor-on-Target (CoT) | **OPEN** — listening |
| 8443 | TCP/HTTPS | WebTAK / Admin UI | **OPEN** — listening (mutual TLS) |
| 8446 | TCP/HTTPS | Certificate enrollment | **OPEN** — listening |

---

## Post-Deployment Test Results

**21 / 22 PASSED** (95.5%)

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | TAK RPM installed | **PASS** | `takserver-5.7-RELEASE8.noarch` |
| 2 | takserver service active | **PASS** | `systemctl is-active takserver` → active |
| 3 | takserver service enabled | **PASS** | `systemctl is-enabled takserver` → enabled |
| 4 | Java 17 installed | **PASS** | `java -version` → openjdk 17 |
| 5 | PostgreSQL running | **PASS** | `systemctl is-active postgresql-*` → active |
| 6 | SELinux policy loaded | **PASS** | `takserver-policy` in semodule list |
| 7 | SELinux enforcing | **PASS** | `getenforce` → Enforcing |
| 8 | Firewall active | **PASS** | `systemctl is-active firewalld` → active |
| 9 | Port 8089 open in firewall | **PASS** | `firewall-cmd --list-ports` includes 8089/tcp |
| 10 | Port 8443 open in firewall | **PASS** | `firewall-cmd --list-ports` includes 8443/tcp |
| 11 | Port 8446 open in firewall | **PASS** | `firewall-cmd --list-ports` includes 8446/tcp |
| 12 | Port 8089 listening | **PASS** | `ss -tlnp` shows java on 8089 |
| 13 | Port 8443 listening | **PASS** | `ss -tlnp` shows java on 8443 |
| 14 | Port 8446 listening | **PASS** | `ss -tlnp` shows java on 8446 |
| 15 | Root CA exists | **PASS** | `/opt/tak/certs/files/root-ca.pem` present |
| 16 | Intermediate CA exists | **PASS** | `/opt/tak/certs/files/intermediate-ca.pem` present |
| 17 | Server cert exists | **PASS** | `/opt/tak/certs/files/takserver.p12` present |
| 18 | Admin cert exists | **PASS** | `/opt/tak/certs/files/admin.p12` present |
| 19 | User cert exists | **PASS** | `/opt/tak/certs/files/user.p12` present |
| 20 | CoreConfig.xml valid XML | **PASS** | `xmllint --noout` exit 0 |
| 21 | Admin promoted | **PASS** | UserManager shows admin with ROLE_ADMIN |
| 22 | WebTAK HTTPS responds | **EXPECTED FAIL** | HTTP 000 — server correctly requires mutual TLS client certificate; unauthenticated curl is rejected |

### Test 22 Explanation

The TAK Server is configured for mutual TLS authentication. An unauthenticated `curl -sk https://localhost:8443/` receives a TLS alert (`bad certificate`, code 554) and returns HTTP 000. This is **correct and expected behaviour** — the server requires a valid client certificate. The server was confirmed listening on port 8443 with `ss -tlnp`.

---

## Client Certificate Files (Downloaded)

The following `.p12` files were downloaded to `C:\GitRepos\DigitalTAK\certs\`:

| File | Size | Purpose |
|------|------|---------|
| `admin.p12` | 4,728 bytes | Browser admin access to WebTAK |
| `user.p12` | 4,726 bytes | ATAK mobile client connection |
| `truststore-root.p12` | 1,208 bytes | Root CA trust chain |

### Browser Access Instructions

1. Import `truststore-root.p12` → Windows Trusted Root Certification Authorities store
2. Import `admin.p12` → Windows Personal certificate store
3. **P12 import password:** (deployment keystore password)
4. Navigate to `https://10.10.0.124:8443`
5. Select the `admin` certificate when prompted

### ATAK Client Instructions

1. Transfer `user.p12` and `truststore-root.p12` to the Android device
2. In ATAK → Settings → Network Preferences → TAK Server Connection
3. Import the certificates using the deployment keystore password
4. Set server address: `10.10.0.124`, port `8089`

---

## Installation Steps Performed

1. **VM Creation** — Hyper-V Gen 2 VM with External vSwitch, Rocky Linux 9 ISO attached
2. **OS Installation** — Rocky Linux 9.7 minimal install with `atak` and `root` users
3. **SSH Configuration** — Passwordless sudo for `atak` via `/etc/sudoers.d/atak`
4. **System Preparation** — Raised nofile ulimit, installed EPEL + base packages
5. **PostgreSQL** — PGDG repo added, built-in module disabled, PostgreSQL installed
6. **Java** — OpenJDK 17 installed, CRB repo enabled
7. **TAK RPM** — Uploaded via SCP (563 MB), installed with `--nogpgcheck`
8. **SELinux** — `checkpolicy` installed, `takserver-policy` compiled and loaded
9. **Service** — `takserver` enabled and started, confirmed active
10. **Firewall** — firewalld installed, ports 8089/8443/8446 opened
11. **Certificate Metadata** — `cert-metadata.sh` patched with org details
12. **Root CA** — Created `TAK-CA` root certificate authority
13. **Intermediate CA** — Created `intermediate-ca` signed by root
14. **Server Cert** — Created `takserver` certificate
15. **Client Certs** — Created `admin` and `user` client certificates
16. **CoreConfig.xml** — Patched trust store, signing block, x509 cache, passwords
17. **Admin Promotion** — `admin.pem` promoted to ROLE_ADMIN via UserManager
18. **Service Restart** — Final restart, confirmed active on all ports
19. **Post-Deployment Tests** — 21/22 passed
20. **Certificate Download** — `.p12` files copied to local machine

---

## Known Issues & Recommendations

| Issue | Severity | Recommendation |
|-------|----------|----------------|
| TAK RPM requires `--nogpgcheck` | Low | TAK GPG key not published to standard repos; verify RPM hash manually |
| Default keystore password `atakatak` | Resolved | All passwords updated during deployment |
| No automated TLS renewal | Info | Run `takserver_createLECerts.sh` for Let's Encrypt if public-facing |
| Cert files are secrets | Critical | `.p12`/`.pem`/`.jks` files must not be committed to Git |

---

## Service Verification (Final State)

```
$ systemctl is-active takserver
active

$ sudo ss -tlnp | grep -E "8089|8443|8446"
LISTEN  0  4096  0.0.0.0:8089  0.0.0.0:*  java (pid 150898)
LISTEN  0  100   0.0.0.0:8443  0.0.0.0:*  java (pid 150899)
LISTEN  0  100   0.0.0.0:8446  0.0.0.0:*  java (pid 150899)
```

---

**Deployment Status: COMPLETE ✓**
