# Deploy-TAKServer.ps1

`Deploy-TAKServer.ps1` is the canonical end-to-end deployment entry point for this repository.

Use it when you want DigitalTAK to build a Rocky Linux 9 TAK Server VM on Hyper-V from your own configuration values rather than running the lower-level Bash scripts manually.

## What It Orchestrates

The script coordinates the full deployment workflow:

1. Creates or resumes a Hyper-V Gen 2 VM.
2. Builds the unattended Rocky Linux installation media artifacts.
3. Waits for SSH access after install or snapshot restore.
4. Uses `TAKInstall` to install TAK Server 5.7.
5. Creates certificates and promotes the admin certificate.
6. Runs post-install validation.
7. Downloads certificate artifacts.
8. Imports the admin and trust certificates into the current Windows user store.
9. Writes `reports/DEPLOYMENT-REPORT.md`.

## When To Use It

Use `Deploy-TAKServer.ps1` when all of the following are true:

- You are operating from a Windows host with Hyper-V.
- You want a reproducible VM build instead of a manual server-side install.
- You want the repository to handle both infrastructure creation and TAK provisioning.

Use `TAKInstall` directly instead when the Rocky host already exists and only SSH-based provisioning is needed.

## Inputs You Must Decide

### VM and platform settings

- VM name
- Hyper-V switch
- Rocky Linux ISO path
- VHDX path and size
- Memory and processor count
- Guest hostname and timezone

### Credentials

- Linux admin credential created by kickstart
- Root password
- TAK keystore password

### Certificate metadata

- State
- City
- Organization
- Organizational Unit
- CA name

If certificate metadata is omitted, the script now prompts for it. For repeatable deployments, pass those values explicitly.

## Execution Patterns

### Guided deployment

Use this pattern when you want the script to prompt for certificate metadata at launch time.

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'

$cred = Get-Credential -UserName 'atak'
$rootPw = Read-Host -AsSecureString -Prompt 'Root password'
$ksPw = Read-Host -AsSecureString -Prompt 'TAK keystore password'

.\Deploy-TAKServer.ps1 `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
    -Confirm:$false
```

### Fully parameterized deployment

Use this pattern when you want no interactive metadata prompts and a stable, rerunnable deployment command.

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'

$cred   = [PSCredential]::new('takadmin', (ConvertTo-SecureString 'ExamplePass!23' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString 'RootExample!23' -AsPlainText -Force
$ksPw   = ConvertTo-SecureString 'KeystoreExample!23' -AsPlainText -Force

.\Deploy-TAKServer.ps1 `
    -VMName 'TAK-Prod-01' `
    -SwitchName 'External LAN' `
    -RockyIsoPath 'D:\ISO\Rocky-9.7-x86_64-dvd.iso' `
    -VHDPath 'D:\VMs\TAK-Prod-01\TAK-Prod-01.vhdx' `
    -VHDSizeBytes 120GB `
    -MemoryBytes 16GB `
    -ProcessorCount 8 `
    -Timezone 'UTC' `
    -Hostname 'tak-prod-01' `
    -RpmPath 'D:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
    -State 'TX' `
    -City 'AUSTIN' `
    -Organization 'ACME-OPS' `
    -OrganizationalUnit 'TAK' `
    -CAName 'ACME-TAK-CA' `
    -Confirm:$false
```

### Resume from checkpoints

The deployment flow supports snapshot-based resume. Re-run the same command to continue from the latest checkpoint.

Checkpoint names:

- `Phase0-RockyInstalled`
- `Phase2-TAKInstalled`
- `Phase4-CertsAndAdmin`

### Force a clean rebuild

Use `-DisableSnapshotResume` when you want to ignore prior checkpoints and rebuild from scratch.

## Outputs

On success, expect:

- A deployed TAK Server VM.
- Downloaded certificate artifacts under `certs/`.
- Imported Windows certificates for admin and trust material.
- A deployment handoff report at `reports/DEPLOYMENT-REPORT.md`.

## Relationship To Other Automation

- `Deploy-TAKServer.ps1` is the highest-level orchestration entry point.
- `TAKInstall` is the provisioning engine used by the script after SSH becomes available.
- `Deploy-TAKTestServer.ps1` remains only as a backward-compatible wrapper.

## Detailed Operator Guide

For the full parameter reference, validation coverage, and delivery details, use the primary operator document at [../Deploy-TAKServer.md](../Deploy-TAKServer.md).