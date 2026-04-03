---
layout: page
title: Client Validation
nav_title: Client Validation
---

# TAK Client Validation Checklist

> **Status:** M4 deliverable — April 2026
> **TAK Server version:** 5.7-RELEASE8
> **Covers:** WinTAK, ATAK (Android), TAKChat (Openfire/XMPP)

---

## Purpose

This checklist documents the expected behaviour when connecting WinTAK and ATAK clients to the DigitalTAK server. Each item is a pass/fail gate. Complete the checklist in order after every full deployment (i.e., after `Deploy-TAKServer.ps1` completes successfully).

Mark each item ✅ pass, ❌ fail, or ⬜ not tested.

---

## 1. Pre-Connection Prerequisites

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 1.1 | TAK Server service running | `systemctl status takserver` → `active (running)` | ⬜ |
| 1.2 | Port 8089 reachable from client workstation | `Test-NetConnection <SERVER_IP> -Port 8089` → `TcpTestSucceeded: True` | ⬜ |
| 1.3 | Port 8443 reachable | `Test-NetConnection <SERVER_IP> -Port 8443` → `TcpTestSucceeded: True` | ⬜ |
| 1.4 | Port 8446 reachable | `Test-NetConnection <SERVER_IP> -Port 8446` → `TcpTestSucceeded: True` | ⬜ |
| 1.5 | Client cert `.p12` file available on device | File exists, not expired (`keytool -list -keystore client.p12`) | ⬜ |
| 1.6 | Server CA cert (`truststore-remote.p12`) available | Exported from `/opt/tak/certs/files/truststore-intermediate-ca.jks` | ⬜ |

---

## 2. WinTAK Validation

### 2.1 Installation

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.1.1 | WinTAK version installed | WinTAK 5.x (current public release) | ⬜ |
| 2.1.2 | WinTAK launches without error | Application opens to map view | ⬜ |

### 2.2 Certificate Import

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.2.1 | Client `.p12` imported via Settings > Network > Manage Server Connections > Certificate | Certificate appears in cert list | ⬜ |
| 2.2.2 | Server CA cert imported to trusted store | No SSL error on connection attempt | ⬜ |

### 2.3 Server Connection

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.3.1 | Data package (`.dp`) imported | Settings pre-populated with server IP and port 8089 | ⬜ |
| 2.3.2 | Connect to TAK Server port 8089 (SSL) | Status bar shows connected; no certificate errors in logs | ⬜ |
| 2.3.3 | Self-SA (own callsign blue force) visible on map | WinTAK icon appears at expected position | ⬜ |
| 2.3.4 | Server-side user entry visible in WebTAK admin | WebTAK `https://<SERVER_IP>:8443` > Users shows WinTAK callsign | ⬜ |

### 2.4 CoT Exchange

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.4.1 | Drop a map marker (CoT event) in WinTAK | Marker appears on server WebTAK map view | ⬜ |
| 2.4.2 | Second connected client sees marker | If two clients present, each sees the other's SA | ⬜ |
| 2.4.3 | Chat message sent from WinTAK | Message visible in WebTAK chat or second client | ⬜ |

### 2.5 Mission Packages

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.5.1 | Mission package upload from WinTAK | Package appears in WebTAK > Mission Packages | ⬜ |
| 2.5.2 | Mission package download to WinTAK | File received, no error | ⬜ |

### 2.6 Group Membership

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 2.6.1 | WinTAK user assigned to group in WebTAK | User appears under group in Configuration > Group Management | ⬜ |
| 2.6.2 | Group filtering applied | Client only sees SA from same group | ⬜ |

---

## 3. ATAK (Android) Validation

### 3.1 Installation

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 3.1.1 | ATAK version installed | ATAK 5.x (current public release); note FIPS-mode certs may not work — standard certs required | ⬜ |
| 3.1.2 | ATAK launches without error | Application opens to map view | ⬜ |

### 3.2 Certificate Import

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 3.2.1 | Data package (`.dp`) sideloaded or downloaded from TAK Server | Settings > Import Manager shows package | ⬜ |
| 3.2.2 | Client cert and CA cert imported | No SSL error; cert appears under Manage Certificates | ⬜ |

### 3.3 Server Connection (port 8089)

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 3.3.1 | Connect to TAK Server port 8089 (SSL, x509 auth) | Status bar shows connected | ⬜ |
| 3.3.2 | Own SA visible on map | ATAK icon at GPS position | ⬜ |
| 3.3.3 | Server-side user entry visible in WebTAK admin | WebTAK shows ATAK callsign | ⬜ |

### 3.4 CoT Exchange & Feature Parity with WinTAK

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 3.4.1 | Drop a map marker in ATAK | Marker visible in WebTAK and WinTAK (if connected) | ⬜ |
| 3.4.2 | WinTAK-created marker visible in ATAK | Matches 2.4.1 result | ⬜ |
| 3.4.3 | Chat message sent from ATAK | Message visible in WebTAK / WinTAK | ⬜ |

### 3.5 Certificate Enrollment (port 8446)

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 3.5.1 | ATAK enrollment request sent to `https://<SERVER_IP>:8446` | TAK Server issues a device certificate | ⬜ |
| 3.5.2 | Enrolled cert used for subsequent connection | Connection succeeds with new per-device cert | ⬜ |

---

## 4. Openfire / TAKChat Validation

### 4.1 Openfire Service

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 4.1.1 | Openfire service running | `systemctl status openfire-xmpp` → `active (running)` | ⬜ |
| 4.1.2 | Port 5222 (XMPP STARTTLS) reachable | `Test-NetConnection <SERVER_IP> -Port 5222` → `TcpTestSucceeded: True` | ⬜ |
| 4.1.3 | Openfire admin console accessible (if admin ports open) | `http://<SERVER_IP>:9090` returns Openfire login page | ⬜ |

### 4.2 TAKChat in WinTAK

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 4.2.1 | TAKChat connection configured (server IP, port 5222) | Settings > TAKChat shows server address | ⬜ |
| 4.2.2 | WinTAK connects to Openfire XMPP | TAKChat status shows connected / green | ⬜ |
| 4.2.3 | Chat message sent via TAKChat | Message delivered; no error in WinTAK logs | ⬜ |

### 4.3 TAKChat in ATAK

| # | Check | Expected | Status |
|---|-------|----------|--------|
| 4.3.1 | ATAK XMPP chat configured to same Openfire server | Settings > Network > XMPP shows connected | ⬜ |
| 4.3.2 | Cross-client chat (ATAK ↔ WinTAK via Openfire) | Message sent from ATAK received in WinTAK TAKChat and vice versa | ⬜ |

---

## 5. Failure Diagnostics

### 5.1 Certificate Errors

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `PKIX path building failed` | Client does not trust the server CA | Re-import `truststore-remote.p12` |
| `bad_certificate` TLS alert | Server does not recognise client cert | Verify client cert was signed by the intermediate CA in `truststore-intermediate-ca.jks` |
| `Connection refused` on 8089 | TAK Server not running, firewalld blocking | `systemctl start takserver`; `firewall-cmd --list-ports` |
| WinTAK prompt for password | Client cert password mismatch | Check `.pref` `clientPassword` field |

### 5.2 Openfire/TAKChat Issues

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Port 5222 refused | Openfire not started | `systemctl start openfire-xmpp` |
| Cockpit blocking port 9090 | Cockpit not disabled | `systemctl disable --now cockpit.socket cockpit` (done by install script) |
| XMPP auth failure | User not provisioned in Openfire | Create user in Openfire admin console; Openfire user provisioning is not automated by this pipeline |

### 5.3 Useful Log Locations

| Component | Log path |
|-----------|---------|
| TAK Server | `/opt/tak/logs/takserver-messaging.log`, `/opt/tak/logs/takserver-api.log` |
| Openfire | `/opt/openfire/logs/openfire.log`, `/opt/openfire/logs/error.log` |
| firewalld | `journalctl -u firewalld` |
| WinTAK | `%APPDATA%\WinTAK\logs\` |
| ATAK | Device internal storage `Android/data/com.atakmap.app/files/logs/` |

---

## 6. Sign-Off

| Validator | Date | Result | Notes |
|-----------|------|--------|-------|
| | | | |

---

## References

- [data-packages.md](./data-packages.md) — building and distributing `.dp` files
- [baseline.md](./baseline.md) — port configuration reference
- [federation.md](./federation.md) — federation configuration
- [TAK Server 5.7 Configuration Guide](../../Documentation/TAK_Server_Configuration_Guide_5.7.md) — §9 Configuration, §12 Federation
