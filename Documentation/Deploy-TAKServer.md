# Deploy-TAKServer.ps1

`Deploy-TAKServer.ps1` is the general-purpose Hyper-V deployment entry point for this repository. It is intended to let an operator deploy a Rocky Linux 9 TAK Server using the modules and supporting assets already present in `DigitalTAK`, while supplying their own configuration values.

## What the script does

The script orchestrates the full deployment flow:

1. Creates a Hyper-V Gen 2 VM
2. Builds an `OEMDRV` kickstart disk for unattended Rocky Linux installation
3. Waits for SSH to come up on the new VM
4. Installs the TAK Server RPM through the `TAKInstall` module
5. Creates CA, server, admin, and user certificates
6. Promotes the admin certificate
7. Runs post-install validation checks
8. Downloads generated `.p12` files
9. Imports the admin and trust certificates into the current Windows user store
10. Generates `reports/DEPLOYMENT-REPORT.md`

## Canonical script names

- Preferred entry point: `Deploy-TAKServer.ps1`
- Backward-compatible wrapper: `Deploy-TAKTestServer.ps1`

Use `Deploy-TAKServer.ps1` for all new deployments.

## Prerequisites

Run the script from an elevated PowerShell 7 session on a Windows host with Hyper-V available.

Required local prerequisites:

- PowerShell 7+
- Hyper-V feature enabled
- A working external Hyper-V vSwitch
- Rocky Linux 9 DVD ISO available locally
- `takserver-5.7-RELEASE8.noarch.rpm` available locally
- `TAKInstall` module present in this repository
- `Posh-SSH` installed for the TAK installation module path

Typical local assets:

- ISO: `C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso`
- RPM: `C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm`

## Configuration model

The script accepts configuration from parameters.

There are three broad groups:

### 1. VM configuration

- `VMName`
- `SwitchName`
- `RockyIsoPath`
- `VHDPath`
- `VHDSizeBytes`
- `MemoryBytes`
- `ProcessorCount`
- `Timezone`
- `Hostname`
- `SSHTimeoutSeconds`

### 2. Credentials

- `Credential` — Linux admin user created by kickstart
- `RootPassword` — Linux root password
- `KeystorePassword` — password for the TAK Server Java keystore
- `CertPassword` — password used when exporting PKCS#12 (`.p12`) certificate files

> **Security requirement:** `-CertPassword` has no default value. The script fails immediately if this parameter is not supplied. Choose a strong, unique password that is not shared with any other system. Do not reuse the `KeystorePassword` value.

### 3. Certificate metadata

- `State`
- `City`
- `Organization`
- `OrganizationalUnit`
- `CAName`

If you omit the certificate metadata fields, the script now prompts for them and offers reusable suggestions instead of silently forcing a fixed lab identity.

## Example deployment modes

### Minimal guided deployment

Use this when you want the script to prompt for certificate subject values while still running unattended after launch.

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'

$cred    = Get-Credential -UserName 'atak'
$rootPw  = Read-Host -AsSecureString -Prompt 'Root password'
$ksPw    = Read-Host -AsSecureString -Prompt 'TAK keystore password'
$certPw  = Read-Host -AsSecureString -Prompt 'Certificate (.p12) password'

.\Deploy-TAKServer.ps1 `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
    -CertPassword $certPw `
    -Confirm:$false
```

The script will prompt for:

- Certificate State
- Certificate City
- Certificate Organization
- Certificate Organizational Unit
- Certificate Authority Name

### Fully parameterized deployment

Use this when you want a reproducible deployment with no metadata prompts.

```powershell
Set-Location 'C:\GitRepos\DigitalTAK'

$cred    = [PSCredential]::new('takadmin', (ConvertTo-SecureString 'ExamplePass!23' -AsPlainText -Force))
$rootPw  = ConvertTo-SecureString 'RootExample!23' -AsPlainText -Force
$ksPw    = ConvertTo-SecureString 'KeystoreExample!23' -AsPlainText -Force
$certPw  = ConvertTo-SecureString 'CertExample!23' -AsPlainText -Force

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
    -CertPassword $certPw `
    -State 'TX' `
    -City 'AUSTIN' `
    -Organization 'ACME-OPS' `
    -OrganizationalUnit 'TAK' `
    -CAName 'ACME-TAK-CA' `
    -Confirm:$false
```

### Resume from snapshots

The script automatically resumes from deployment checkpoints if they exist.

Checkpoint names:

- `Phase0-RockyInstalled`
- `Phase2-TAKInstalled`
- `Phase4-CertsAndAdmin`

Run the same command again to resume from the latest deployment checkpoint.

### Force a clean rebuild

Use `-DisableSnapshotResume` when you want the script to ignore prior checkpoints and rebuild the VM from scratch.

```powershell
.\Deploy-TAKServer.ps1 `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
    -CertPassword $certPw `
    -DisableSnapshotResume `
    -Confirm:$false
```

## Parameter guidance

### VM settings

- `VMName`: Hyper-V VM name to create or resume
- `SwitchName`: external Hyper-V vSwitch used for network access
- `RockyIsoPath`: full path to the Rocky Linux DVD ISO
- `VHDPath`: full path to the VM disk file to create
- `VHDSizeBytes`: maximum size of the dynamic VHDX
- `MemoryBytes`: fixed startup memory assigned to the VM
- `ProcessorCount`: number of vCPUs assigned to the VM
- `Timezone`: guest OS timezone written into kickstart
- `Hostname`: hostname assigned during unattended install
- `SSHTimeoutSeconds`: timeout while waiting for SSH after install or snapshot restore

### Credentials

- `Credential`: the Linux admin account created by kickstart and used for SSH
- `RootPassword`: root account password written into kickstart
- `KeystorePassword`: password for the TAK Server Java keystore; recorded in the deployment report
- `CertPassword`: password used when creating and exporting PKCS#12 (`.p12`) certificate files — `admin.p12`, `user.p12`, and `truststore-intermediate-ca.p12`; also used when importing those certificates into the Windows certificate store

**`CertPassword` requirements:**

- **Mandatory** — the script fails immediately with an error if this parameter is not supplied. There is no default.
- Use a strong, unique password (minimum 8 characters; mix of upper/lower case, digits, and symbols recommended).
- Do not reuse the `KeystorePassword` value for this parameter.
- Record this password securely; it is required any time a client imports the `.p12` files.

### Certificate metadata

These values are written into `/opt/tak/certs/cert-metadata.sh` and used when creating CA and service certificates:

- `State`
- `City`
- `Organization`
- `OrganizationalUnit`
- `CAName`

Allowed format:

- uppercase letters
- digits
- hyphens

Examples:

- `TX`
- `AUSTIN`
- `ACME-OPS`
- `FIELD-TEAM`
- `ACME-TAK-CA`

## Outputs and deliverables

On a successful run, the script produces:

- a deployed TAK Server VM
- local certificate downloads under `certs/`
- Windows certificate store imports for the admin and trust material
- deployment report at `reports/DEPLOYMENT-REPORT.md`

Primary remote outputs:

- `/home/atak/admin.p12`
- `/home/atak/user.p12`
- `/home/atak/truststore-intermediate-ca.p12`

## Validation coverage

The script validates:

- `takserver` service state
- Java presence
- PostgreSQL state
- TLS listener ports
- firewalld rules
- SELinux module load
- certificate artifact presence
- certificate-enrollment HTTPS reachability
- RPM presence
- host OS identity

## Recommended usage pattern

For routine use:

1. Prepare ISO, RPM, and Hyper-V switch
2. Decide your VM sizing and naming
3. Decide your certificate subject metadata before launch
4. Run `Deploy-TAKServer.ps1` with explicit parameters for repeatable deployments
5. Use snapshot resume for recovery during iterative setup
6. Review `reports/DEPLOYMENT-REPORT.md` after completion

## Notes

- The wrapper `Deploy-TAKTestServer.ps1` remains only for backward compatibility.
- New operational documentation should reference `Deploy-TAKServer.ps1`.
- If you want the cert subject metadata to be fully reproducible, pass it explicitly instead of relying on the prompts.

## Migration note for existing deployments

Previous versions of this script generated `.p12` files using a hardcoded community password. That default has been removed.

**If you have existing `.p12` files generated before this change:**

- Those files were protected with the old community password, which is publicly known. They should be treated as compromised.
- After upgrading to this version of the script, re-run the certificate generation step by running a new deployment (or using snapshot resume from before the cert phase). Supply a fresh, strong `-CertPassword` value.
- Redistribute the new `.p12` files to all ATAK/WinTAK clients and update any automated import scripts that previously used the old default.
- Remove or revoke the old `.p12` files from client devices where possible.