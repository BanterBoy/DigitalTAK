# DigitalTAK Wiki

This is the repository's wiki section for operators and maintainers working with the PowerShell automation in DigitalTAK.

It is organized around the three main ways to work with the repository:

1. Use the end-to-end deployment script when you want to build a full Hyper-V TAK Server VM from your own configuration.
2. Use the `TAKInstall` module when you already have a Rocky Linux 9 host and want to provision or extend it over SSH.
3. Use the `TAKServerPS` module when the server is already running and you want to manage it through the TAK Server REST API.

## Pages

| Page | Purpose |
|------|---------|
| [Deploy-TAKServer.md](Deploy-TAKServer.md) | When to use the deployment script, what it configures, and the main execution patterns. |
| [TAKInstall.md](TAKInstall.md) | Remote provisioning module reference for installation, certificates, Openfire, and Let's Encrypt. |
| [TAKServerPS.md](TAKServerPS.md) | REST API module reference for sessions, users, missions, feeds, certificates, security, and server inventory. |

## Choose The Right Entry Point

| Task | Recommended Entry Point |
|------|-------------------------|
| Build a new TAK Server VM on Hyper-V | `Deploy-TAKServer.ps1` |
| Install TAK Server on an existing Rocky Linux 9 host over SSH | `Install-TAKServer` from `TAKInstall` |
| Create TAK CA and service certificates over SSH | `New-TAKServerCertificate` from `TAKInstall` |
| Promote the admin certificate over SSH | `Set-TAKAdminCertificate` from `TAKInstall` |
| Install Openfire chat integration | `Install-TAKOpenfire` from `TAKInstall` |
| Issue or renew Let's Encrypt certificates | `New-TAKLetsEncryptCertificate` or `Update-TAKLetsEncryptCertificate` |
| Manage users, missions, feeds, inputs, and other server resources after deployment | `TAKServerPS` |

## Typical Lifecycle

### 1. Deployment

- Start with [Deploy-TAKServer.md](Deploy-TAKServer.md) if you want a full Windows-hosted Hyper-V deployment flow.
- Use [TAKInstall.md](TAKInstall.md) directly if the VM or server already exists and only provisioning is required.

### 2. Post-install configuration

- Use `TAKInstall` for SSH-driven server-side changes that map to the bundled Bash scripts.
- Use `TAKServerPS` for REST API operations after the TAK Server web interface and API are reachable.

### 3. Ongoing operations

- Use `TAKServerPS` for day-2 tasks such as user administration, mission management, inputs, feeds, outgoing connections, and certificate inventory.
- Use `TAKInstall` for host-level maintenance such as Openfire deployment and Let's Encrypt renewal workflows.

## Repository Context

- Shell script implementation lives under `InstallShellScripts/`.
- TXT mirrors live under `TXTScripts/` and must remain byte-identical to the shell scripts.
- The PowerShell modules wrap those shell-driven workflows and the TAK REST API so operators can drive the platform from Windows PowerShell 7.

## Recommended Reading Order

1. [Deploy-TAKServer.md](Deploy-TAKServer.md)
2. [TAKInstall.md](TAKInstall.md)
3. [TAKServerPS.md](TAKServerPS.md)

## Related Documents

- [../Documentation/Deploy-TAKServer.md](../Documentation/Deploy-TAKServer.md)
- [../Documentation/TAK_Server_Configuration_Guide_5.7.pdf](../Documentation/TAK_Server_Configuration_Guide_5.7.pdf)
- [../Documentation/Federation_Hub_Configuration_Guide.pdf](../Documentation/Federation_Hub_Configuration_Guide.pdf)