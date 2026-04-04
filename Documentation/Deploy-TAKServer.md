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
7. Runs post-install validation checks (22 tests)
8. Downloads generated `.p12` files to `certs/` on the Windows host
9. Generates `reports/DEPLOYMENT-REPORT-<timestamp>.md`

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
- `VMBasePath` — base directory for VM storage; the script creates `<VMBasePath>\<VMName>\` automatically. Defaults to `C:\Hyper-V\VMs`
- `VHDPath` — optional override for the VHDX path; if omitted, derived as `<VMBasePath>\<VMName>\<VMName>.vhdx`
- `VHDSizeBytes`
- `MemoryBytes`
- `ProcessorCount`
- `Timezone`
- `Hostname`
- `SSHTimeoutSeconds`

### 2. Credentials

- `Credential` — Linux admin user created by kickstart
- `RootPassword` — Linux root password
- `KeystorePassword` — single password used for all of: the TAK Server Java keystores, the `CAPASS` value written to `cert-metadata.sh`, the PKCS#12 (`.p12`) export passphrase, and any subsequent import of those `.p12` files into browser or application stores

> **Security requirement:** `-KeystorePassword` has no default. The script fails immediately if this parameter is not supplied. Choose a strong password that is not shared with any other system.

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

$cred   = Get-Credential -UserName 'atak'
$rootPw = Read-Host -AsSecureString -Prompt 'Root password'
$ksPw   = Read-Host -AsSecureString -Prompt 'TAK keystore / certificate password'

.\Deploy-TAKServer.ps1 `
    -Credential $cred `
    -RootPassword $rootPw `
    -KeystorePassword $ksPw `
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

$cred   = [PSCredential]::new('takadmin', (ConvertTo-SecureString 'ExamplePass!23' -AsPlainText -Force))
$rootPw = ConvertTo-SecureString 'RootExample!23' -AsPlainText -Force
$ksPw   = ConvertTo-SecureString 'KeystoreExample!23' -AsPlainText -Force

.\Deploy-TAKServer.ps1 `
    -VMName 'TAK-Prod-01' `
    -VMBasePath 'D:\Hyper-V\VMs' `
    -SwitchName 'External LAN' `
    -RockyIsoPath 'D:\ISO\Rocky-9.7-x86_64-dvd.iso' `
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
    -DisableSnapshotResume `
    -Confirm:$false
```

## Parameter guidance

### VM settings

- `VMName`: Hyper-V VM name to create or resume
- `SwitchName`: external Hyper-V vSwitch used for network access
- `RockyIsoPath`: full path to the Rocky Linux DVD ISO
- `VMBasePath`: base directory for VM storage. The script creates `<VMBasePath>\<VMName>\` and places both the VHDX and the OEMDRV staging disk there. Default: `C:\Hyper-V\VMs`
- `VHDPath`: full path to the VM disk file. If not supplied, derived as `<VMBasePath>\<VMName>\<VMName>.vhdx`
- `VHDSizeBytes`: maximum size of the dynamic VHDX
- `MemoryBytes`: fixed startup memory assigned to the VM
- `ProcessorCount`: number of vCPUs assigned to the VM
- `Timezone`: guest OS timezone written into kickstart
- `Hostname`: hostname assigned during unattended install
- `SSHTimeoutSeconds`: timeout while waiting for SSH after install or snapshot restore

### Credentials

- `Credential`: the Linux admin account created by kickstart and used for SSH
- `RootPassword`: root account password written into kickstart
- `KeystorePassword`: single password used for all certificate material — written to `CAPASS` in `cert-metadata.sh`, applied to every Java keystore (`.jks`) and every PKCS#12 (`.p12`) export on the server, and embedded in `CoreConfig.xml`

**`KeystorePassword` requirements:**

- **Mandatory** — the script fails immediately if this parameter is not supplied. There is no default.
- Use a strong, unique password (minimum 8 characters; mix of upper/lower case, digits, and symbols recommended).
- Record this password securely — it is required any time a `.p12` file is imported into a browser or ATAK client.

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

- a deployed TAK Server VM running TAK Server 5.7-RELEASE8
- certificate artifacts downloaded to `certs/` on the Windows host
- a timestamped deployment report at `reports/DEPLOYMENT-REPORT-<yyyyMMddHHmmss>.md`

Primary remote outputs (also SFTPed locally):

- `/home/atak/admin.p12` — admin browser certificate; protected with `KeystorePassword`
- `/home/atak/user.p12` — sample user certificate; protected with `KeystorePassword`
- `/home/atak/truststore-intermediate-ca.p12` — intermediate CA trust anchor; protected with `KeystorePassword`

> These `.p12` files are **not** automatically imported into the Windows certificate store. Import them manually using the `KeystorePassword` when prompted.

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

Previous versions of this script used the publicly-known default keystore password `atakatak` for all certificate material. That default is now replaced by the mandatory `-KeystorePassword` parameter.

**If you have `.p12` files generated before this change:**

- Those files were protected with `atakatak`, which is publicly known. Treat them as compromised.
- Run a clean deployment (or resume from the `Phase2-TAKInstalled` snapshot) and supply a strong `-KeystorePassword`.
- Redistribute the new `.p12` files to all ATAK/WinTAK clients.
- Remove the old `.p12` files from client devices where possible.