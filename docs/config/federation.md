---
layout: page
title: TAK Server Federation
nav_title: Federation
---

# TAK Server Federation Configuration

> **Status:** M4 stub — April 2026
> **TAK Server version:** 5.7-RELEASE8
> **Source:** TAK Server 5.7 Configuration Guide §12 and Federation Hub Configuration Guide

---

## 1. Overview

Federation allows ATAK/WinTAK users connected to separate TAK Server instances (across independent administrative domains) to share situational awareness (SA) without direct cross-domain client connections.

Key properties:

- Each domain retains full control over what data it shares outbound.
- ATAKs on one server are never directly exposed to the other server's network.
- Trust is established by exchanging CA certificates (or tokens), not user accounts.
- No ATAK/WinTAK client reconfiguration is required to participate in federation.

**DigitalTAK lab scope:** Single-node federation is not applicable to a single-server lab. This document is a configuration reference for when a second TAK Server instance is available. The federation configuration settings in CoreConfig.xml are **not touched** by the current pipeline scripts.

---

## 2. Federation Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 9000 | TCP (TLS v1) | Legacy federation protocol (TAK Server ≤ 5.x) |
| 9001 | TCP (TLS v2) | Current federation protocol (v2, preferred) |
| Token port | TCP (configurable) | Token-based auth federation (alternative to mTLS) |

> Federation ports are not opened by `RL9_tak5.7r8_install.sh`. Add them manually to firewalld if federation is required:
>
> ```bash
> firewall-cmd --permanent --add-port=9001/tcp
> firewall-cmd --reload
> ```

---

## 3. Enabling Federation

Federation is enabled via the **WebTAK admin UI** — there is no CLI or CoreConfig.xml entry to set directly.

1. Navigate to `https://<SERVER_IP>:8443` and log in with the admin certificate.
2. Go to **Configuration > Manage Federates**.
3. Click **Edit Configuration**.
4. Enable federation and select the protocol version (v2 / port 9001 recommended).
5. **Restart TAK Server** after saving — federation port changes require a restart.

```bash
# On the TAK Server host
systemctl restart takserver
```

---

## 4. Certificate Exchange

For federated servers to trust each other's clients, each server must upload the other server's CA certificate.

### 4.1 Export Your CA

```bash
# On Server A — export the intermediate CA public cert
openssl x509 -in /opt/tak/certs/files/intermediate-ca.pem -out /tmp/server-a-ca.pem
```

Exchange `server-a-ca.pem` with the administrator of Server B via a secure out-of-band channel (email, USB, secure file transfer).

### 4.2 Upload Peer CA to TAK Server

1. In WebTAK: **Configuration > Federate Certificate Authorities > Upload CA**.
2. Upload the `.pem` file received from the peer.
3. The peer CA is stored in a separate federate truststore — it does **not** grant that CA's clients direct ATAK access to your server.

---

## 5. Outgoing Connection (Initiating Server)

Only **one** server initiates the connection. The other listens passively.

1. WebTAK: **Configuration > Manage Federates > Outgoing Connection Configuration**.
2. Enter peer server address and port (e.g., `<PEER_IP>:9001`).
3. Select protocol version v2.
4. Set reconnection interval (default: 5 seconds).
5. Enable connection.

Verify in **Active Connections** — the connection status should show `Connected`.

---

## 6. Group Filtering

After connection, no data flows until groups are configured on both servers.

1. In **Manage Federates > Federate Configuration**, locate the connected peer row.
2. Click **Manage Groups**.
3. Add the group names (or `__ANON__` for ungrouped clients) that you want to share outbound.
4. The peer must mirror this step for their groups.
5. No restart required — group changes take effect immediately.

### 6.1 Federated Group Mapping (Optional)

Incoming traffic from remote groups can be mapped to local groups. This allows cross-domain group normalisation without exposing internal group names.

1. In **Federate Groups > Federated Group Mapping**, select a remote group from the dropdown.
2. Map it to a local group.
3. Traffic from the remote group is inserted into the mapped local group.

---

## 7. Token-Based Authentication (Alternative to mTLS)

Token auth is useful when network inspection (TLS break-and-inspect) prevents mutual TLS.

### 7.1 Enable Token Auth

1. WebTAK: **Configuration > Federation** — enable token authentication and set a token port.

### 7.2 Issue a Manual Token

1. Navigate to **Federate Token Generation** in **Configuration > Federation**.
2. Generate a token and distribute it to the peer admin.
3. The peer enters the token in their outgoing connection configuration.

> The peer still needs your CA cert (`ca.pem`) for TLS trust even when using tokens.

---

## 8. Mission Federation Disruption Tolerance

Enables mission synchronisation catch-up after a federation link outage.

| Setting | Default | Notes |
|---------|---------|-------|
| Enabled | Off | Check box in Federation Configuration page |
| Send changes newer than | 2 days | Configurable per mission; `Unlimited` option available |

Enable in WebTAK: **Configuration > Manage Federates > Federation Configuration > Mission Federation Disruption Tolerance**.

---

## 9. Data Package and Mission File Blocker

Prevents federated `.pref` files and other config artefacts from propagating to remote clients.

1. WebTAK: **Configuration > Manage Federates > Federation Configuration**.
2. Check **Data Package and Mission File Blocker**.
3. Default blocked extension: `pref`. Add additional extensions as needed.

---

## 10. DigitalTAK Pipeline Gaps

The following federation items are **not implemented** in the current pipeline and require manual setup:

| Item | Notes |
|------|-------|
| Firewalld rules for port 9001 | Not opened by `RL9_tak5.7r8_install.sh` |
| Federation enabled in CoreConfig.xml | No script in repo touches federation settings |
| Peer CA exchange | Requires out-of-band coordination |
| Group filter configuration | Manual WebTAK admin step |

---

## 11. Federation Hub (Separate Install)

For hub-and-spoke topologies (multiple servers federated through a central relay), TAK provides a separate **Federation Hub** installer. This is distinct from the TAK Server federation described above.

Key differences:

| Feature | TAK Server Federation | Federation Hub |
|---------|----------------------|----------------|
| Architecture | Peer-to-peer | Hub-and-spoke |
| Install package | Included with TAK Server | Separate RPM (`takserver-fed-hub-*.noarch.rpm`) |
| Purpose | Two organisations share SA | Multiple enclaves through one central relay |
| DigitalTAK status | Documented (this stub) | Out of scope for current lab |

Refer to `Documentation/Federation_Hub_Configuration_Guide.pdf` and the TAK.gov wiki for Federation Hub setup.

---

## References

- [TAK Server 5.7 Configuration Guide §12](../../Documentation/TAK_Server_Configuration_Guide_5.7.md#12-federation)
- [Federation Hub Configuration Guide](../../Documentation/Federation_Hub_Configuration_Guide.pdf)
- [TAK.gov wiki — Federation Hub](https://wiki.tak.gov/display/TPC/Federation+Hub)
- [baseline.md](./baseline.md) — CoreConfig settings not managed by pipeline
- [client-validation.md](./client-validation.md) — post-deployment validation checklist
