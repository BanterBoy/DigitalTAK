# TAKServerPS Module

`TAKServerPS` is the REST API administration module for DigitalTAK.

Use it after TAK Server is already installed and reachable on the management interface. The module establishes a shared session with `Connect-TAKServer` and then exposes resource-oriented cmdlets for common TAK Server administration tasks.

## What The Module Is For

Use `TAKServerPS` when you want to manage a running TAK Server through the API instead of shell access.

Typical use cases:

- user administration,
- mission creation and subscription management,
- data feed and input management,
- outgoing connection management,
- certificate inventory,
- security configuration review and updates,
- server inventory and metadata queries.

## Requirements

- PowerShell 7+
- Network access to the TAK Server management port
- Valid authentication material for one of the supported `Connect-TAKServer` parameter sets

Import the module with:

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1
```

## Session Model

Connect once at the start of the session. The module stores the server session in module state so the remaining cmdlets do not need the connection details repeated on every call.

### Certificate authentication

```powershell
$pass = Read-Host -AsSecureString -Prompt 'PFX password'
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -PfxPath '.\admin.p12' -PfxPassword $pass
```

### Username and password authentication

```powershell
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Credential (Get-Credential)
```

### Token authentication

```powershell
$token = Read-Host -AsSecureString -Prompt 'API token'
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Token $token
```

Disconnect when finished:

```powershell
Disconnect-TAKServer
```

## Exported Functions

### Session

| Cmdlet | Purpose |
|--------|---------|
| `Connect-TAKServer` | Establishes a session to a TAK Server instance. |
| `Disconnect-TAKServer` | Ends the current TAK Server session. |

### Users and groups

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKUser` | Gets users from a connected TAK Server. |
| `New-TAKUser` | Creates a new file-managed user on a connected TAK Server. |
| `Remove-TAKUser` | Deletes a file-managed user from a connected TAK Server. |
| `Set-TAKUserPassword` | Changes the password for a file-managed TAK Server user. |
| `Set-TAKUserGroup` | Updates group membership for a file-managed TAK Server user. |
| `Get-TAKGroup` | Gets groups from a connected TAK Server. |
| `Get-TAKContact` | Gets contacts from a connected TAK Server. |
| `Get-TAKSubscription` | Gets one or all client subscriptions on a connected TAK Server. |
| `Remove-TAKSubscription` | Removes a client subscription from a connected TAK Server. |

### Missions

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKMission` | Gets missions from a connected TAK Server. |
| `New-TAKMission` | Creates a new mission on a connected TAK Server. |
| `Remove-TAKMission` | Deletes a mission from a connected TAK Server. |
| `Get-TAKMissionChange` | Gets change history for a TAK Server mission. |
| `Get-TAKMissionContact` | Gets contacts associated with a TAK Server mission. |
| `Get-TAKMissionSubscription` | Gets subscriptions for a TAK Server mission. |
| `Register-TAKMissionSubscription` | Subscribes a client UID to a TAK Server mission. |
| `Unregister-TAKMissionSubscription` | Removes a client subscription from a TAK Server mission. |

### Certificates and security

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKCertificate` | Gets TAK Server client certificates. |
| `Invoke-TAKCertificateSign` | Signs a client certificate signing request using the TAK Server CA. |
| `Remove-TAKCertificate` | Revokes and removes a TAK Server client certificate. |
| `Get-TAKSecurityConfig` | Gets the security configuration from a connected TAK Server. |
| `Set-TAKSecurityConfig` | Updates the security configuration on a connected TAK Server. |
| `Remove-TAKToken` | Revokes or removes API tokens on a connected TAK Server. |

### Data exchange

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKDataFeed` | Gets data feeds from a connected TAK Server. |
| `New-TAKDataFeed` | Creates a new data feed on a connected TAK Server. |
| `Remove-TAKDataFeed` | Removes a data feed from a connected TAK Server. |
| `Get-TAKInput` | Gets one or all inputs configured on a connected TAK Server. |
| `New-TAKInput` | Creates a new network input on a connected TAK Server. |
| `Remove-TAKInput` | Removes a network input from a connected TAK Server. |
| `Get-TAKOutgoingConnection` | Gets outgoing TCP/TLS connections configured on a connected TAK Server. |
| `New-TAKOutgoingConnection` | Creates a new outgoing connection on a connected TAK Server. |
| `Remove-TAKOutgoingConnection` | Removes an outgoing connection from a connected TAK Server. |

### Content and media

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKMapLayer` | Gets map layers from a connected TAK Server. |
| `Remove-TAKMapLayer` | Removes a map layer from a connected TAK Server. |
| `Get-TAKVideo` | Gets video connection configurations from a connected TAK Server. |
| `New-TAKVideo` | Creates a new video connection on a connected TAK Server. |
| `Remove-TAKVideo` | Removes a video connection from a connected TAK Server. |
| `Get-TAKPlugin` | Gets plugin information from a connected TAK Server. |
| `Get-TAKDeviceProfile` | Gets the device enrollment profile from a connected TAK Server. |

### Server state and federation

| Cmdlet | Purpose |
|--------|---------|
| `Get-TAKVersion` | Gets version information from a connected TAK Server. |
| `Get-TAKCoT` | Gets Cursor-on-Target (CoT) events from a connected TAK Server. |
| `Get-TAKFederate` | Gets federate server configurations from a connected TAK Server. |

## Common Usage Patterns

### Inspect server state

```powershell
Connect-TAKServer -Server 'takserver.example.com' -Port 8443 -Credential (Get-Credential)
Get-TAKVersion
Get-TAKSecurityConfig
Get-TAKFederate
```

### User administration

```powershell
$password = Read-Host -AsSecureString -Prompt 'User password'

New-TAKUser -Username 'jsmith' -Password $password
Set-TAKUserGroup -Username 'jsmith' -GroupName 'Blue'
Set-TAKUserPassword -Username 'jsmith' -Password $password
Get-TAKUser
```

### Mission management

```powershell
$mission = New-TAKMission -Name 'Field-Exercise-01'
Get-TAKMission
Get-TAKMissionChange -MissionId $mission.id
Register-TAKMissionSubscription -MissionId $mission.id -Uid 'ANDROID-DEVICE-001'
```

### Feeds and inputs

```powershell
Get-TAKDataFeed
New-TAKInput -Name 'Partner TLS Feed' -Protocol 'tls'
Get-TAKOutgoingConnection
```

### Certificate review

```powershell
Get-TAKCertificate | Where-Object { $_.expiration -lt (Get-Date).AddDays(30) }
```

## When Not To Use It

Do not use `TAKServerPS` for host provisioning, certificate file generation on the server filesystem, Openfire installation, or Let's Encrypt bootstrap. Those are SSH-driven tasks owned by `TAKInstall` and the deployment script.

## Related Pages

- [Home.md](Home.md)
- [Deploy-TAKServer.md](Deploy-TAKServer.md)
- [TAKInstall.md](TAKInstall.md)