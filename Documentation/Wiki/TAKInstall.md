# TAKInstall Module

`TAKInstall` is the SSH-driven provisioning module in this repository.

It is the PowerShell layer that drives the server-side installation and configuration workflows on an existing Rocky Linux 9 host. Conceptually, it is the PowerShell equivalent of the Bash scripts under `InstallShellScripts/`.

## What The Module Is For

Use `TAKInstall` when you already have network access to a Rocky Linux 9 server and want to:

- install TAK Server,
- create or update certificates,
- promote the admin certificate,
- add Openfire chat integration,
- issue or renew Let's Encrypt certificates.

## Requirements

- PowerShell 7+
- `Posh-SSH`
- SSH access to the Rocky Linux 9 host
- TAK Server RPM available on the target host or transferable during your workflow

Import the module with:

```powershell
Install-Module Posh-SSH -Scope CurrentUser
Import-Module .\TAKInstall\TAKInstall.psd1
```

## Typical Workflow

```powershell
$ssh = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

Install-TAKServer -SshSession $ssh -RpmPath '/tmp/takserver-5.7-RELEASE8.noarch.rpm'

New-TAKServerCertificate -SshSession $ssh `
    -State 'TX' `
    -City 'AUSTIN' `
    -Organization 'ACME-OPS' `
    -OrganizationalUnit 'TAK' `
    -KeystorePassword $pass

Set-TAKAdminCertificate -SshSession $ssh
```

## Exported Functions

| Cmdlet | Purpose | When To Use It |
|--------|---------|----------------|
| `Install-TAKServer` | Installs TAK Server 5.7-RELEASE8 on a Rocky Linux 9 host via SSH. | Initial server provisioning on a new or rebuilt host. |
| `New-TAKServerCertificate` | Creates the TAK Server certificate authority, server certificate, and client certificate set over SSH. | After the base RPM install, when enabling x509 auth and enrollment. |
| `Set-TAKAdminCertificate` | Promotes the TAK Server admin certificate to the administrator role via SSH. | After certificate creation, so the admin client cert has administrator privileges. |
| `Install-TAKOpenfire` | Installs Openfire XMPP Server on a Rocky Linux 9 TAK Server host via SSH. | Optional chat deployment when TAK Chat / XMPP is required. |
| `New-TAKLetsEncryptCertificate` | Issues a Let's Encrypt TLS certificate for a TAK Server host via SSH. | When replacing self-signed HTTPS with a public certificate. |
| `Update-TAKLetsEncryptCertificate` | Renews the Let's Encrypt TLS certificate on a TAK Server host via SSH. | Ongoing certificate maintenance after initial Let's Encrypt setup. |

## Common Usage Patterns

### Install TAK Server only

```powershell
$ssh = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
Install-TAKServer -SshSession $ssh -RpmPath '/tmp/takserver-5.7-RELEASE8.noarch.rpm'
```

### Create certificates and enable x509

```powershell
$pass = Read-Host -AsSecureString -Prompt 'Keystore password'

New-TAKServerCertificate -SshSession $ssh `
    -State 'TX' `
    -City 'AUSTIN' `
    -Organization 'ACME-OPS' `
    -OrganizationalUnit 'TAK' `
    -CAName 'ACME-TAK-CA' `
    -KeystorePassword $pass
```

### Promote the admin certificate

```powershell
Set-TAKAdminCertificate -SshSession $ssh
```

### Install Openfire

```powershell
Install-TAKOpenfire -SshSession $ssh
```

### Issue a Let's Encrypt certificate

```powershell
New-TAKLetsEncryptCertificate -SshSession $ssh `
    -Domain 'tak.example.com' `
    -Email 'admin@example.com'
```

### Renew a Let's Encrypt certificate

```powershell
Update-TAKLetsEncryptCertificate -SshSession $ssh
```

## How It Maps To The Shell Scripts

| `TAKInstall` Cmdlet | Primary Shell Script |
|---------------------|----------------------|
| `Install-TAKServer` | `InstallShellScripts/RL9_tak5.7r8_install.sh` |
| `New-TAKServerCertificate` | `InstallShellScripts/createTakCerts.sh` and `InstallShellScripts/takUserCreateCerts_doNotRunAsRoot.sh` |
| `Set-TAKAdminCertificate` | `InstallShellScripts/promoteAdmin.sh` |
| `Install-TAKOpenfire` | `InstallShellScripts/openfire_takChat_install.sh` |
| `New-TAKLetsEncryptCertificate` | `InstallShellScripts/takserver_createLECerts.sh` |
| `Update-TAKLetsEncryptCertificate` | `InstallShellScripts/takserver_renewLECerts.sh` |

## When Not To Use It

Do not use `TAKInstall` for day-2 API administration such as user inventory, mission control, feeds, or subscriptions. Use `TAKServerPS` for those tasks instead.

## Related Pages

- [Home.md](Home.md)
- [Deploy-TAKServer.md](Deploy-TAKServer.md)
- [TAKServerPS.md](TAKServerPS.md)