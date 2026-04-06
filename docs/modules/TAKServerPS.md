---
layout: page
title: TAKServerPS Module
nav_title: TAKServerPS
---

# TAKServerPS Module (TAKServer)

**Module file:** `TAKServerPS\TAKServer.psd1`
**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** none (uses `Invoke-WebRequest` / .NET `HttpClient` internally)

## Purpose

TAKServerPS is a REST API wrapper for TAK Server 5.x. It provides 44 cmdlets covering users, groups, missions, certificates, network inputs, data feeds, video, federation, and more. All cmdlets share a module-scoped session established with `Connect-TAKServer`.

## Installing

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1
```

## Session Management

All cmdlets require an active session. Establish one with `Connect-TAKServer` and end it with `Disconnect-TAKServer`.

```powershell
# Certificate auth (most common — uses admin.p12)
Connect-TAKServer -HostName tak.example.com `
    -PfxPath C:\certs\admin.p12 `
    -PfxPassword (Read-Host -AsSecureString)

# Basic auth
Connect-TAKServer -HostName tak.example.com -Credential (Get-Credential)

# End session
Disconnect-TAKServer
```

By default, server certificate validation is skipped (`-SkipCertificateCheck $true`) because TAK Server ships with a self-signed certificate. Set `-SkipCertificateCheck $false` only when using a trusted certificate (e.g. Let's Encrypt).

---

## Cmdlet Reference

### Session

#### `Connect-TAKServer`

Establishes a session and stores it in module scope.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `HostName` | String | Yes | Hostname or IP address of the TAK Server |
| `Port` | Int | No | HTTPS port (default: 8443) |
| `Certificate` | X509Certificate2 | No | Client certificate object (Certificate set) |
| `PfxPath` | String | No (Pfx set) | Path to `.pfx`/`.p12` file |
| `PfxPassword` | SecureString | No | Password for the PFX file |
| `Credential` | PSCredential | No (Credential set) | Basic auth credential |
| `Token` | SecureString | No (Token set) | Pre-obtained Bearer token |
| `SkipCertificateCheck` | Bool | No | Skip server cert validation (default: `$true`) |

**Outputs:** `PSCustomObject` (the active session object)

#### `Disconnect-TAKServer`

Calls `/logout` and clears the module-scoped session.

| Parameter | Type | Description |
|-----------|------|-------------|
| `Force` | Switch | Clear local session without calling the remote logout endpoint |

---

### Server Info

#### `Get-TAKVersion`

| Parameter | Type | Description |
|-----------|------|-------------|
| `Detailed` | Switch | Return full VersionInfo object (build date, git commit). Default returns short version string. |

```powershell
Get-TAKVersion           # "5.7-RELEASE-8"
Get-TAKVersion -Detailed # Full build object
```

---

### Users

#### `Get-TAKUser`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns all currently connected users |
| `AccountList` | Switch | Returns all provisioned file-managed user accounts |
| `GroupName` | String | Returns accounts belonging to the specified group |
| `ConnectionId` | String | Returns the user record for a specific connection UID |

```powershell
Get-TAKUser                               # Connected users
Get-TAKUser -AccountList                  # All accounts
Get-TAKUser -AccountList -GroupName 'Ops' # Accounts in Ops group
Get-TAKUser -ConnectionId 'ANDROID-abc'   # Specific connection
```

#### `New-TAKUser`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Credential` | PSCredential | Yes | Username and password for the new account |
| `GroupList` | String[] | No | Bi-directional group memberships |
| `InboundGroups` | String[] | No | Inbound-only group memberships |
| `OutboundGroups` | String[] | No | Outbound-only group memberships |

```powershell
$cred = Get-Credential -UserName 'fielduser1'
New-TAKUser -Credential $cred -GroupList 'Operators'
New-TAKUser -Credential $cred -InboundGroups 'Intel' -OutboundGroups 'Command'
```

#### `Remove-TAKUser`

| Parameter | Type | Description |
|-----------|------|-------------|
| `UserName` | String | Username to delete (pipeline-compatible) |
| `AlsoRevokeCertificates` | Switch | Revoke all certs for the user before deleting |

```powershell
Remove-TAKUser -UserName 'exuser1'
Remove-TAKUser -UserName 'exuser1' -AlsoRevokeCertificates
Get-TAKUser -AccountList | Where-Object { $_.username -like 'temp_*' } | Remove-TAKUser
```

#### `Set-TAKUserPassword`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Credential` | PSCredential | Yes | Username and new password |

```powershell
Set-TAKUserPassword -Credential (Get-Credential -UserName 'fielduser1')
```

---

### Groups

#### `Get-TAKGroup`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns all groups visible to the current user |
| `Name` | String | Specific group by name |
| `Direction` | `IN`\|`OUT` | Filter by direction (used with `-Name`) |
| `All` | Switch | Returns all groups including hidden (admin only) |

```powershell
Get-TAKGroup
Get-TAKGroup -All
Get-TAKGroup -Name 'Operators' -Direction IN
```

#### `Set-TAKUserGroup`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `UserName` | String | Yes | Username to update |
| `GroupList` | String[] | No | Bi-directional memberships to set |
| `InboundGroups` | String[] | No | Inbound-only memberships |
| `OutboundGroups` | String[] | No | Outbound-only memberships |

```powershell
Set-TAKUserGroup -UserName 'fielduser1' -GroupList 'Operators', 'Command'
Set-TAKUserGroup -UserName 'sensor1' -InboundGroups 'Intel' -OutboundGroups 'FieldTeam'
```

---

### Certificates

#### `Get-TAKCertificate`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All certificates |
| `UserName` | String | Filter by username |
| `Active` | Switch | Active certs only |
| `Revoked` | Switch | Revoked certs only |
| `Expired` | Switch | Expired certs only |

```powershell
Get-TAKCertificate
Get-TAKCertificate -UserName 'fielduser1'
Get-TAKCertificate -Expired
```

#### `Invoke-TAKCertificateSign`

Signs a PEM-encoded CSR using the TAK Server CA.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `CsrPem` | String | Yes | PEM-encoded CSR string (pipeline-compatible) |
| `Version2` | Switch | No | Use the `/v2` signing endpoint |

```powershell
$csr = Get-Content 'client.csr' -Raw
Invoke-TAKCertificateSign -CsrPem $csr
```

#### `Remove-TAKCertificate`

Revokes a certificate by its SHA-256 fingerprint hash.

| Parameter | Type | Description |
|-----------|------|-------------|
| `Hash` | String | Certificate hash (pipeline-compatible by value or `hash` property) |

```powershell
Remove-TAKCertificate -Hash 'abc123...'
Get-TAKCertificate -Expired | Remove-TAKCertificate
```

---

### Contacts and CoT

#### `Get-TAKContact`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SortBy` | `CALLSIGN`\|`UID` | `CALLSIGN` | Sort field |
| `Direction` | `ASCENDING`\|`DESCENDING` | `ASCENDING` | Sort direction |
| `NoFederates` | Switch | | Exclude federated contacts |
| `Full` | Switch | | Return full contact records including group mapping |

```powershell
Get-TAKContact
Get-TAKContact -SortBy UID -NoFederates
Get-TAKContact -Full
```

#### `Get-TAKCoT`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | Returns current SA track for all contacts |
| `Uid` | String | Returns CoT XML for a specific UID |

```powershell
Get-TAKCoT
Get-TAKCoT -Uid 'ANDROID-abc123'
```

---

### Missions

#### `Get-TAKMission`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All missions |
| `Name` | String | Single mission by name |
| `Guid` | String | Single mission by GUID |
| `Tool` | String | Filter list by tool type (e.g. `public`, `vbm`) |
| `PasswordProtected` | Switch | Filter to password-protected missions |
| `IncludeChanges` | Switch | Include change log (single-mission mode) |
| `IncludeLogs` | Switch | Include log entries (single-mission mode) |
| `SecAgo` | Long | Content changed within last N seconds |
| `Start` | DateTime | Content changed after this time |
| `End` | DateTime | Content changed before this time |

```powershell
Get-TAKMission
Get-TAKMission -Name 'OpBlue'
Get-TAKMission -Tool 'public' -IncludeChanges
```

#### `New-TAKMission`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique mission name |
| `Description` | String | No | Human-readable description |
| `Group` | String[] | No | Groups to assign (default: `__ANON__`) |
| `Tool` | String | No | Tool type (default: `public`) |
| `ChatRoom` | String | No | Associated chat room |
| `BaseLayer` | String | No | Base map layer name |
| `Bbox` | String | No | Bounding box (`minLon,minLat,maxLon,maxLat`) |
| `Classification` | String | No | Classification label |
| `Password` | SecureString | No | Access password |
| `DefaultRole` | String | No | `MISSION_OWNER`, `MISSION_SUBSCRIBER`, or `MISSION_READONLY_SUBSCRIBER` |
| `InviteOnly` | Switch | No | Restrict to invited members |
| `Expiration` | Long | No | Unix timestamp expiry; `-1` for none (default) |

```powershell
New-TAKMission -Name 'OpBlue' -Description 'Op Blue mission' -Group 'TeamAlpha'
New-TAKMission -Name 'IntelBrief' -Tool 'vbm' -InviteOnly -DefaultRole MISSION_READONLY_SUBSCRIBER
```

#### `Remove-TAKMission`

```powershell
Remove-TAKMission -Name 'OpBlue'
Get-TAKMission -Tool 'test' | Remove-TAKMission
```

#### `Get-TAKMissionChange`

| Parameter | Type | Description |
|-----------|------|-------------|
| `Name` | String | Mission name (required) |
| `SecAgo` | Long | Changes in the last N seconds |
| `Start` / `End` | DateTime | Date range filter |

#### `Get-TAKMissionContact`

Returns contacts associated with a mission.

```powershell
Get-TAKMissionContact -Name 'OpBlue'
```

#### `Get-TAKMissionSubscription`

Returns active subscriptions for a mission.

```powershell
Get-TAKMissionSubscription -Name 'OpBlue'
```

#### `Register-TAKMissionSubscription`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `MissionName` | String | Yes | Mission to subscribe to |
| `Uid` | String | Yes | TAK client UID |
| `Role` | String | No | `MISSION_OWNER`, `MISSION_SUBSCRIBER` (default), `MISSION_READONLY_SUBSCRIBER` |

```powershell
Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'
Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123' -Role MISSION_OWNER
```

#### `Unregister-TAKMissionSubscription`

```powershell
Unregister-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'
```

---

### Network Inputs

#### `Get-TAKInput`

```powershell
Get-TAKInput           # All inputs
Get-TAKInput -Name 'UDPInput'
```

#### `New-TAKInput`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique input name |
| `Protocol` | String | Yes | `tcp`, `udp`, `stcp`, `tcp_ssl`, `udp_broadcast` |
| `Port` | Int | Yes | Port to listen on (1–65535) |
| `Group` | String[] | No | Groups this input feeds |
| `Interface` | String | No | Bind address (default: `0.0.0.0`) |
| `Archive` | Switch | No | Archive received events |
| `AnonGroup` | Switch | No | Allow anonymous clients |
| `ArchiveOnly` | Switch | No | Store only, do not forward |
| `FederateOnly` | Switch | No | Forward to federates only |
| `AuthRequired` | Switch | No | Require client authentication |

```powershell
New-TAKInput -Name 'SACast' -Protocol udp -Port 4242
New-TAKInput -Name 'TLSClients' -Protocol tcp_ssl -Port 8089 -AuthRequired -Archive
```

#### `Remove-TAKInput`

```powershell
Remove-TAKInput -Name 'SACast'
Get-TAKInput | Where-Object port -gt 9000 | Remove-TAKInput -Confirm:$false
```

---

### Data Feeds

#### `Get-TAKDataFeed`

| Parameter | Type | Description |
|-----------|------|-------------|
| *(none)* | | All data feed configurations |
| `Name` | String | Single feed by name |
| `Uuid` | String | Single feed by UUID (returns stats) |
| `Stats` | Switch | Stats for all feeds |

#### `New-TAKDataFeed`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Name` | String | Yes | Unique feed name |
| `Protocol` | String | Yes | `tcp`, `udp`, `stcp`, `tcp_ssl`, `udp_broadcast` |
| `Port` | Int | Yes | Port (1–65535) |
| `Group` | String[] | No | Groups this feed delivers to |
| `Interface` | String | No | Bind address (default: `0.0.0.0`) |
| `Archive` | Switch | No | Archive events |
| `AnonGroup` | Switch | No | Allow anonymous clients |
| `Type` | String | No | Feed type (e.g. `Full`, `Diff`) |
| `Tag` | String | No | Tag string |
| `Sync` | Switch | No | Enable data sync |

```powershell
New-TAKDataFeed -Name 'SensorFeed' -Protocol udp -Port 6666 -Group 'Operators'
New-TAKDataFeed -Name 'TLSFeed' -Protocol tcp_ssl -Port 8089 -Group '__ANON__' -Archive
```

#### `Remove-TAKDataFeed`

```powershell
Remove-TAKDataFeed -Name 'SensorFeed'
Get-TAKDataFeed | Where-Object protocol -eq 'udp' | Remove-TAKDataFeed -Confirm:$false
```

---

### Subscriptions

#### `Get-TAKSubscription`

```powershell
Get-TAKSubscription                    # All subscriptions
Get-TAKSubscription -Uid 'ANDROID-abc' # Specific subscription
```

#### `Remove-TAKSubscription`

```powershell
Remove-TAKSubscription -Uid 'ANDROID-abc'
Get-TAKSubscription | Where-Object callsign -like 'OLD-*' | Remove-TAKSubscription -Confirm:$false
```

---

### Video Connections

#### `Get-TAKVideo`

```powershell
Get-TAKVideo
Get-TAKVideo | Where-Object active -eq $true
```

#### `New-TAKVideo`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Alias` | String | Yes | Friendly display name |
| `Feeds` | Object[] | Yes | Feed objects — each must have at least a `url` property |
| `Uuid` | String | No | UUID (auto-generated if omitted) |
| `Active` | Bool | No | Visible to clients (default: `$true`) |
| `Thumbnail` | String | No | Thumbnail URL or path |
| `Classification` | String | No | Classification marking (e.g. `U//FOUO`) |

```powershell
$feed = @{ url = 'rtsp://10.0.0.50:8554/live'; type = 'rtsp' }
New-TAKVideo -Alias 'Drone Camera 1' -Feeds $feed
```

#### `Remove-TAKVideo`

```powershell
Remove-TAKVideo -Uid '7b3c9a2e-...'
Get-TAKVideo | Where-Object active -eq $false |
    Select-Object -ExpandProperty uuid |
    Remove-TAKVideo -Confirm:$false
```

---

### Outgoing Connections

#### `Get-TAKOutgoingConnection`

```powershell
Get-TAKOutgoingConnection
Get-TAKOutgoingConnection | Where-Object enabled -eq $true
```

#### `New-TAKOutgoingConnection`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Address` | String | Yes | Remote hostname or IP |
| `Port` | Int | Yes | Remote TCP port (1–65535) |
| `DisplayName` | String | Yes | Friendly name |
| `Tls` | Switch | No | Use TLS |
| `ProtocolVersion` | Int | No | Protocol version (default: 1) |
| `ReconnectInterval` | Int | No | Seconds between reconnect attempts (default: 10) |
| `MaxRetries` | Int | No | Max reconnect attempts (ignored if `-UnlimitedRetries`) |
| `UnlimitedRetries` | Switch | No | Retry indefinitely |
| `Enabled` | Bool | No | Active immediately (default: `$true`) |
| `ConnectionToken` | String | No | Optional token for the connect handshake |
| `UseToken` | Switch | No | Include token in handshake |

```powershell
New-TAKOutgoingConnection -Address 'tak.example.com' -Port 8089 -Tls -DisplayName 'HQ Server'
New-TAKOutgoingConnection -Address '10.0.0.5' -Port 8087 -DisplayName 'Field Hub' -UnlimitedRetries
```

#### `Remove-TAKOutgoingConnection`

```powershell
Remove-TAKOutgoingConnection -Name 'HQ Server'
Get-TAKOutgoingConnection | Where-Object enabled -eq $false |
    Select-Object -ExpandProperty displayName |
    Remove-TAKOutgoingConnection -Confirm:$false
```

---

### Federation

#### `Get-TAKFederate`

```powershell
Get-TAKFederate
Get-TAKFederate | Where-Object enabled -eq $true
```

---

### Security Configuration

#### `Get-TAKSecurityConfig`

Returns TLS settings, cipher suites, and authentication policy.

```powershell
Get-TAKSecurityConfig
```

#### `Set-TAKSecurityConfig`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Config` | Object | Yes | Security config object (from `Get-TAKSecurityConfig`) |

```powershell
$cfg = Get-TAKSecurityConfig
$cfg.auth = 'ldap'
Set-TAKSecurityConfig -Config $cfg
```

---

### Other

#### `Get-TAKPlugin`

Returns metadata for all installed TAK Server plugins.

```powershell
Get-TAKPlugin
```

#### `Get-TAKMapLayer` / `Remove-TAKMapLayer`

```powershell
Get-TAKMapLayer
Get-TAKMapLayer -Uid '7b3c9a2e-...'
Remove-TAKMapLayer -Uid '7b3c9a2e-...'
Get-TAKMapLayer | Where-Object name -like 'TEMP_*' | Remove-TAKMapLayer -Confirm:$false
```

#### `Get-TAKDeviceProfile`

Returns the device enrollment/provisioning profile (settings pushed to enrolled TAK clients).

```powershell
Get-TAKDeviceProfile
```

#### `Remove-TAKToken`

| Parameter | Type | Description |
|-----------|------|-------------|
| `Token` | String | Single token to delete |
| `Tokens` | String[] | Multiple tokens to bulk-revoke |

```powershell
Remove-TAKToken -Token 'eyJhbGci...'
Remove-TAKToken -Tokens 'token1', 'token2', 'token3'
```

---

## Gaps and Known Issues

- No `Set-TAKMission` cmdlet — mission update requires `New-TAKMission` (the API uses idempotent PUT).
- No cmdlets for TAK Server log retrieval or export.
- No cmdlets for mission file attachment management (add/remove files from missions).
- No `New-TAKFederate` / `Remove-TAKFederate` — federate configuration must be done via WebTAK or direct API.
- `Get-TAKGroup` with `-Name` always queries the IN direction by default; passing `-Direction OUT` is required for outbound-only group inspection.
