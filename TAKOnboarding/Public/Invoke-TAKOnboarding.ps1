<#
.SYNOPSIS
    One-command TAK Server team onboarding — certificates, user accounts, and ATAK data packages.

.DESCRIPTION
    Performs the complete onboarding workflow for a new team against an already-deployed
    TAK Server instance. No Linux experience required; all SSH/SFTP operations are handled
    automatically.

    Workflow:
      1. Verify prerequisites (Posh-SSH, TAKServerPS, keytool, admin.p12)
      2. Generate per-user client certificates on the TAK Server via SSH
      3. Download the .p12 files and manifest to this Windows workstation via SFTP
      4. Delete cert files from the server (security hygiene)
      5. Create TAK Server user accounts via UserManager.jar over SSH
      6. Assign group memberships via UserManager.jar over SSH
      7. Build per-user ATAK data packages (.zip) ready to distribute

    At the end of the run you will have a folder of per-user .zip files ready to send
    to your team members, and all accounts provisioned on the server.

.PARAMETER ServerHost
    Hostname or IP address of the TAK Server (e.g. 10.10.0.154).

.PARAMETER TakPort
    TAK Server HTTPS / WebTAK port (default: 8443).

.PARAMETER CotPort
    TAK Server Cursor-on-Target (CoT) SSL port (default: 8089).

.PARAMETER SshCredential
    SSH credential for the server (account with sudo rights). Prompted if not supplied.

.PARAMETER SshPort
    SSH port on the TAK Server (default: 22).

.PARAMETER AdminPfxPath
    Path to admin.p12 — used to authenticate REST API calls via TAKServerPS.
    Prompted if not supplied.

.PARAMETER AdminPfxPassword
    Password for admin.p12 as a SecureString. Prompted if not supplied.

.PARAMETER KeystorePassword
    TAK Server certificate keystore password (set during deployment).
    Used to unlock per-user .p12 files and the truststore. Prompted if not supplied.

.PARAMETER TeamName
    Name of the team to onboard (e.g. alpha, bravo). Lowercase letters/digits/hyphens.

.PARAMETER TeamSize
    Number of people in the team — 10 or 20.
    Team composition:
      1  Team Lead       -> <TeamName>-lead
      1  Assistant Lead  -> <TeamName>-asst-lead
      N  Operators       -> <TeamName>-op-01 ... <TeamName>-op-NN
    Mutually exclusive with -RosterPath.

.PARAMETER RosterPath
    Path to a CSV or JSON file defining a custom user roster.
    When provided, -TeamSize is not required.

    CSV format (required columns: Username, Role; optional: ExtraGroups):
        Username,Role,ExtraGroups
        john.doe,Team Lead,
        jane.smith,Operator,isr;recon

    JSON format:
        [
          { "username": "john.doe",   "role": "Team Lead" },
          { "username": "jane.smith", "role": "Operator", "extraGroups": ["isr","recon"] }
        ]

    Recognised roles: 'Team Lead', 'Assistant Lead', 'Operator'.
    ExtraGroups are assigned in addition to role-based groups.

.PARAMETER UserPassword
    Initial password for all created accounts as a SecureString.
    TAK Server requires minimum 15 characters with upper, lower, digit, and special character.
    Prompted if not supplied.

.PARAMETER ServerDescription
    Human-readable server name shown in the ATAK server list (default: "TAK Server").

.PARAMETER OutputDir
    Directory for per-user .zip data packages. Default: <DeploymentRoot>\dist\<TeamName>

.PARAMETER LocalCertDir
    Directory for downloaded .p12 and manifest files. Default: <DeploymentRoot>\certs\<TeamName>

.PARAMETER DeploymentRoot
    Root folder of the DigitalTAK repository checkout. Used to locate
    TAKServerPS, onboarding scripts, certs\, and dist\.
    Defaults to the current working directory.

.PARAMETER SkipCertGeneration
    Skip cert generation and download. Requires an existing manifest.json in LocalCertDir.

.PARAMETER SkipUserCreation
    Skip user account creation and group assignment.

.PARAMETER SkipDataPackages
    Skip ATAK data package build step.

.PARAMETER Force
    Suppress confirmation prompts for destructive steps (cert deletion from server).

.EXAMPLE
    PS> Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName alpha -TeamSize 10

    Minimal — prompts for all credentials.

.EXAMPLE
    PS> $ssh  = [PSCredential]::new('atak', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))
    PS> $pfxP = ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force
    PS> $ksP  = ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force
    PS> $uP   = ConvertTo-SecureString 'TeamAlpha!Secure2026' -AsPlainText -Force
    PS> Invoke-TAKOnboarding -ServerHost 10.10.0.154 -SshCredential $ssh `
            -AdminPfxPath .\certs\admin.p12 -AdminPfxPassword $pfxP `
            -KeystorePassword $ksP -TeamName alpha -TeamSize 10 -UserPassword $uP

    Fully scripted.

.EXAMPLE
    PS> Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo `
            -RosterPath .\onboarding\rosters\sample-roster-10.csv -AdminPfxPath .\certs\admin.p12

    Custom roster from CSV.

.EXAMPLE
    PS> Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo -TeamSize 10 `
            -SkipCertGeneration -LocalCertDir .\certs\bravo

    Skip cert generation (certs already in .\certs\bravo).

.NOTES
    ESAPI BUG (TAK Server 5.7-RELEASE8)
    The REST endpoint POST /Marti/api/users/ throws HTTP 500. This cmdlet works around
    it by running UserManager.jar directly on the server over SSH.

    PREREQUISITES
    - PowerShell 7.0+
    - Posh-SSH:    Install-Module Posh-SSH -Scope CurrentUser -Force
    - TAKServerPS: in this repo at <DeploymentRoot>\TAKServerPS\TAKServer.psd1
    - JDK 11+ with keytool on PATH (only needed when -SkipDataPackages is not set)
    - admin.p12 from the server
#>
function Invoke-TAKOnboarding {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'AutoRoster')]
    param (
        #region Connection
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ServerHost,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $TakPort = 8443,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $CotPort = 8089,

        [Parameter()]
        [PSCredential] $SshCredential,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $SshPort = 22,

        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $AdminPfxPath,

        [Parameter()]
        [SecureString] $AdminPfxPassword,
        #endregion

        #region Team
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]{0,29}$')]
        [string] $TeamName,

        [Parameter(ParameterSetName = 'AutoRoster', Mandatory)]
        [ValidateSet('10', '20')]
        [string] $TeamSize,

        [Parameter(ParameterSetName = 'CustomRoster')]
        [ValidateScript({
            if (-not (Test-Path $_ -PathType Leaf)) { throw "Roster file not found: $_" }
            if ($_ -notmatch '\.(csv|json)$') { throw 'RosterPath must be a .csv or .json file' }
            $true
        })]
        [string] $RosterPath,

        [Parameter()]
        [SecureString] $KeystorePassword,

        [Parameter()]
        [SecureString] $UserPassword,

        [Parameter()]
        [string] $ServerDescription = 'TAK Server',
        #endregion

        #region Output
        [Parameter()]
        [string] $OutputDir,

        [Parameter()]
        [string] $LocalCertDir,

        [Parameter()]
        [string] $DeploymentRoot = (Get-Location).Path,
        #endregion

        #region Switches
        [Parameter()]
        [switch] $SkipCertGeneration,

        [Parameter()]
        [switch] $SkipUserCreation,

        [Parameter()]
        [switch] $SkipDataPackages,

        [Parameter()]
        [switch] $Force
        #endregion
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # ── Step 1: Prerequisites ─────────────────────────────────────────────────────
    Write-TAKBanner 'TAK Server Team Onboarding'
    Write-Host "  Server : $ServerHost`:$TakPort"
    if ($PSCmdlet.ParameterSetName -eq 'CustomRoster') {
        Write-Host "  Team   : $TeamName  (custom roster: $(Split-Path $RosterPath -Leaf))"
    }
    else {
        Write-Host "  Team   : $TeamName  ($TeamSize people, auto-template)"
    }
    Write-Host "  Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    Write-TAKStep 1 'Checking prerequisites'

    $modulePath = Join-Path $DeploymentRoot 'TAKServerPS\TAKServer.psd1'
    if (-not (Test-Path $modulePath)) {
        throw "TAKServerPS module not found at '$modulePath'. Set -DeploymentRoot to the DigitalTAK repo root."
    }
    Import-Module $modulePath -Force
    Write-TAKOk "TAKServerPS loaded ($((Get-Module TAKServer).Version))"

    if (-not (Get-Module -ListAvailable Posh-SSH)) {
        Write-Host '  Posh-SSH not installed. Installing...' -ForegroundColor Yellow
        Install-Module Posh-SSH -Scope CurrentUser -Force
    }
    Import-Module Posh-SSH -Force
    Write-TAKOk 'Posh-SSH loaded'

    if (-not $SkipDataPackages) {
        $keytoolPath = Find-TAKKeytool
        if (-not $keytoolPath) {
            Write-TAKWarn 'keytool not found. Install JDK 11+ from https://adoptium.net or use -SkipDataPackages.'
            throw 'keytool not found — cannot build ATAK data packages.'
        }
        Write-TAKOk "keytool: $keytoolPath"
    }

    # Collect credentials
    if (-not $SshCredential)    { $SshCredential    = Get-Credential -Message "SSH credentials for $ServerHost (sudo rights required)" }
    if (-not $AdminPfxPath)     { $AdminPfxPath     = Read-Host 'Path to admin.p12'; if (-not (Test-Path $AdminPfxPath -PathType Leaf)) { throw "admin.p12 not found at '$AdminPfxPath'" } }
    if (-not $AdminPfxPassword) { $AdminPfxPassword = Read-Host -AsSecureString 'Password for admin.p12' }
    if (-not $KeystorePassword) { $KeystorePassword = Read-Host -AsSecureString 'TAK Server keystore password (set during deployment)' }
    if (-not $UserPassword -and -not $SkipUserCreation) {
        Write-Host "  Set an initial password for all $TeamName accounts (min 15 chars, upper+lower+digit+special)." -ForegroundColor Cyan
        $UserPassword = Read-Host -AsSecureString "Initial password for $TeamName users"
    }

    $resolvedCertDir   = if ($LocalCertDir) { $LocalCertDir } else { Join-Path $DeploymentRoot "certs\$TeamName" }
    $resolvedOutputDir = if ($OutputDir)    { $OutputDir    } else { Join-Path $DeploymentRoot "dist\$TeamName"  }
    $null = New-Item -ItemType Directory -Force -Path $resolvedCertDir
    $null = New-Item -ItemType Directory -Force -Path $resolvedOutputDir
    Write-TAKOk "Cert staging : $resolvedCertDir"
    Write-TAKOk "Data packages: $resolvedOutputDir"

    $resolvedUserList = if ($PSCmdlet.ParameterSetName -eq 'CustomRoster') {
        $imported = Import-TAKRosterFile -Path $RosterPath -TeamFilter $TeamName
        Write-TAKOk "Custom roster: $($imported.Count) users from $(Split-Path $RosterPath -Leaf) (team: $TeamName)"
        $imported
    }
    else {
        $generated = Build-TAKUserList -Team $TeamName -Size ([int]$TeamSize)
        Write-TAKOk "Auto roster: $($generated.Count) users ($TeamName template)"
        $generated
    }

    # ── Steps 2-4: Certificates ───────────────────────────────────────────────────
    $sshSession  = $null
    $sftpSession = $null

    try {
        if (-not $SkipCertGeneration) {
            Write-TAKStep 2 'Generating client certificates on TAK Server'

            Write-Host "  Connecting to $ServerHost`:$SshPort..." -ForegroundColor DarkGray
            $sshSession = New-SSHSession -ComputerName $ServerHost -Port $SshPort `
                              -Credential $SshCredential -AcceptKey -Force -ErrorAction Stop
            Write-TAKOk 'SSH session established'

            $sftpSession = New-SFTPSession -ComputerName $ServerHost -Port $SshPort `
                               -Credential $SshCredential -AcceptKey -Force
            Write-TAKOk 'SFTP session established'

            $remoteTeamDir = "/opt/tak/certs/files/teams/$TeamName"

            if ($PSCmdlet.ParameterSetName -eq 'AutoRoster') {
                $localScript = Join-Path $DeploymentRoot "onboarding\tak-team-certs.sh"
                if (-not (Test-Path $localScript)) { throw "tak-team-certs.sh not found at '$localScript'." }
                Set-SFTPItem -SessionId $sftpSession.SessionId -Path $localScript -Destination '/tmp' -Force
                Invoke-TAKSSHCommand $sshSession 'chmod 755 /tmp/tak-team-certs.sh' 'chmod script'

                $ksPwPlain = ConvertFrom-TAKSecureString $KeystorePassword
                $cmd       = "export TAK_CERT_PASS='" + $ksPwPlain + "'; sudo -E -u tak bash /tmp/tak-team-certs.sh --team $TeamName --size $TeamSize"
                $ksPwPlain = $null

                Write-Host '  Running tak-team-certs.sh (this takes about 30 seconds per user)...' -ForegroundColor DarkGray
                $certOut = Invoke-TAKSSHCommand $sshSession $cmd 'tak-team-certs.sh' -TimeoutSec (90 * ([int]$TeamSize + 2))
                $certOut | ForEach-Object { Write-Verbose "  REMOTE: $_" }
                Write-TAKOk 'Certificate generation complete'
            }
            else {
                Write-Host "  Generating $($resolvedUserList.Count) custom-roster certificates..." -ForegroundColor DarkGray
                Invoke-TAKSSHCommand $sshSession "sudo -u tak mkdir -p '$remoteTeamDir'" 'create team cert dir'

                foreach ($rUser in $resolvedUserList) {
                    $rName = $rUser.Username
                    Invoke-TAKSSHCommand $sshSession "yes | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeCert.sh client $rName'" "cert: $rName" -TimeoutSec 60 | Out-Null
                    Invoke-TAKSSHCommand $sshSession "sudo -u tak cp /opt/tak/certs/files/${rName}.p12 '$remoteTeamDir/'" "stage: $rName" | Out-Null
                    Write-TAKOk "Certificate: $rName"
                }

                $tsCmd = "sudo -u tak bash -c 'cd /opt/tak/certs/files && ([ -f truststore-intermediate-ca.p12 ] && cp truststore-intermediate-ca.p12 $remoteTeamDir/ || cp truststore-intermediate-ca.jks $remoteTeamDir/ 2>/dev/null || true)'"
                Invoke-TAKSSHCommand $sshSession $tsCmd 'stage truststore' -TimeoutSec 15 | Out-Null
                Write-TAKOk 'Truststore staged'
            }

            Invoke-TAKSSHCommand $sshSession "test -d '$remoteTeamDir'" 'verify cert dir' | Out-Null
            Write-TAKOk "Remote cert directory confirmed: $remoteTeamDir"

            Invoke-TAKSSHCommand $sshSession "sudo chmod 755 '$remoteTeamDir' && sudo chmod 644 '$remoteTeamDir'/*" 'chmod cert dir for SFTP'

            Write-TAKStep 3 'Downloading certificates to Windows workstation'

            $remoteFiles = Invoke-TAKSSHCommand $sshSession "ls '$remoteTeamDir/'" 'list cert dir'
            Write-Host "  Downloading from $remoteTeamDir..." -ForegroundColor DarkGray
            foreach ($file in ($remoteFiles | Where-Object { $_ -match '\.(p12|jks|json)$' })) {
                Get-SFTPItem -SessionId $sftpSession.SessionId -Path "$remoteTeamDir/$file" -Destination $resolvedCertDir -Force
                Write-TAKOk "Downloaded: $file"
            }

            $manifestPath = Join-Path $resolvedCertDir 'manifest.json'

            if ($PSCmdlet.ParameterSetName -eq 'CustomRoster') {
                $manifestData = @{
                    team  = $TeamName
                    users = @($resolvedUserList | ForEach-Object { @{ username = $_.Username; role = $_.Role } })
                }
                $manifestData | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
                Write-TAKOk 'manifest.json written from custom roster'
            }
            elseif (-not (Test-Path $manifestPath)) {
                throw "manifest.json was not downloaded. Check remote directory: $remoteTeamDir"
            }

            Write-TAKStep 4 'Deleting certificates from server (security hygiene)'
            $confirmed = $Force -or $PSCmdlet.ShouldProcess("$remoteTeamDir on $ServerHost", 'Delete team cert directory (already downloaded)')
            if ($confirmed) {
                Invoke-TAKSSHCommand $sshSession "sudo rm -rf '$remoteTeamDir'" 'remove remote cert dir'
                Write-TAKOk "Deleted from server: $remoteTeamDir"
            }
            else {
                Write-TAKWarn "Skipped. Remember to manually delete $remoteTeamDir from the server."
            }
        }
        else {
            Write-TAKStep 2 'Certificate generation skipped (-SkipCertGeneration)'
            $manifestPath = Join-Path $resolvedCertDir 'manifest.json'
            if (-not (Test-Path $manifestPath)) {
                throw "No manifest.json in '$resolvedCertDir'. Run without -SkipCertGeneration or set -LocalCertDir."
            }
            Write-TAKSkip "Using existing certs in $resolvedCertDir"
            Write-TAKOk 'manifest.json found'
        }

        # ── Steps 5-6: User accounts ──────────────────────────────────────────────
        if (-not $SkipUserCreation) {
            Write-TAKStep 5 'Creating TAK Server user accounts'
            Write-Host '  (Via UserManager.jar over SSH — REST bypass for TAK 5.7-RELEASE8)' -ForegroundColor DarkGray

            if (-not $sshSession -or -not $sshSession.Connected) {
                Write-Host '  Opening SSH session...' -ForegroundColor DarkGray
                $sshSession = New-SSHSession -ComputerName $ServerHost -Port $SshPort `
                                  -Credential $SshCredential -AcceptKey -Force
                Write-TAKOk 'SSH session established'
            }

            Invoke-TAKSSHCommand $sshSession 'test -f /opt/tak/utils/UserManager.jar' 'check UserManager.jar' | Out-Null
            Write-TAKOk 'UserManager.jar found on server'

            Connect-TAKServer -HostName $ServerHost -Port $TakPort `
                              -PfxPath $AdminPfxPath -PfxPassword $AdminPfxPassword `
                              -SkipCertificateCheck $true
            Write-TAKOk "TAK Server REST API connected — $(Get-TAKVersion)"

            $uPwPlain = ConvertFrom-TAKSecureString $UserPassword
            $created  = 0
            $skipped  = 0
            $failed   = 0

            foreach ($user in $resolvedUserList) {
                $username = $user.Username
                $role     = $user.Role

                try {
                    $allAccounts = Get-TAKUser -AccountList
                    $exists      = $allAccounts | Where-Object { $_.username -eq $username }
                }
                catch {
                    $exists = $null
                }

                if ($exists) {
                    Write-TAKSkip "$username (already exists)"
                    $skipped++
                    continue
                }

                try {
                    Invoke-TAKSSHCommand $sshSession "sudo java -jar /opt/tak/utils/UserManager.jar usermod -p '$uPwPlain' $username" "create: $username" | Out-Null
                    Write-TAKOk "$username  ($role)"
                    $created++
                }
                catch {
                    Write-TAKFail "$username — $($_.Exception.Message)"
                    $failed++
                }
            }

            $uPwPlain = $null
            [System.GC]::Collect()

            Write-Host ''
            $userResultColor = if ($failed -gt 0) { 'Yellow' } else { 'Green' }
            $userResultMsg   = "  Results: $created created, $skipped skipped$(if ($failed -gt 0) { ", $failed FAILED" })"
            Write-Host $userResultMsg -ForegroundColor $userResultColor

            Write-TAKStep 6 'Assigning group memberships'

            $allUsersGroup = $TeamName
            $leadsGroup    = "${TeamName}-Lead"

            foreach ($user in $resolvedUserList) {
                $username    = $user.Username
                $role        = $user.Role
                $extraGroups = if ($user.ExtraGroups) { $user.ExtraGroups } else { @() }

                try {
                    Invoke-TAKSSHCommand $sshSession "sudo java -jar /opt/tak/utils/UserManager.jar usermod -g $allUsersGroup $username" "group: $username -> $allUsersGroup" | Out-Null
                    Write-TAKOk "$username -> $allUsersGroup"
                }
                catch {
                    Write-TAKWarn "$username group assignment failed: $($_.Exception.Message)"
                }

                if ($role -in 'Team Lead', 'Assistant Lead') {
                    try {
                        Invoke-TAKSSHCommand $sshSession "sudo java -jar /opt/tak/utils/UserManager.jar usermod -g $leadsGroup $username" "group: $username -> $leadsGroup" | Out-Null
                        Write-TAKOk "$username -> $leadsGroup"
                    }
                    catch {
                        Write-TAKWarn "$username leads group failed: $($_.Exception.Message)"
                    }
                }

                foreach ($xGroup in $extraGroups) {
                    try {
                        Invoke-TAKSSHCommand $sshSession "sudo java -jar /opt/tak/utils/UserManager.jar usermod -g $xGroup $username" "group: $username -> $xGroup" | Out-Null
                        Write-TAKOk "$username -> $xGroup (extra)"
                    }
                    catch {
                        Write-TAKWarn "$username extra group '$xGroup' failed: $($_.Exception.Message)"
                    }
                }
            }

            Write-Host ''
            Write-Host "  Groups: $allUsersGroup (all), $leadsGroup (leads only)" -ForegroundColor DarkGray
        }
        else {
            Write-TAKStep 5 'User creation skipped (-SkipUserCreation)'
        }

        # ── Step 7: ATAK data packages ────────────────────────────────────────────
        if (-not $SkipDataPackages) {
            Write-TAKStep 7 'Building ATAK data packages'

            New-TAKDataPackage `
                -ManifestPath         (Join-Path $resolvedCertDir 'manifest.json') `
                -CertDir              $resolvedCertDir `
                -ServerHostname       $ServerHost `
                -ServerPort           $CotPort `
                -ServerDescription    $ServerDescription `
                -CertPassphrase       $KeystorePassword `
                -TrustStorePassphrase $KeystorePassword `
                -OutputDir            $resolvedOutputDir

            Write-TAKOk "Data packages written to: $resolvedOutputDir"
        }
        else {
            Write-TAKStep 7 'Data package build skipped (-SkipDataPackages)'
        }
    }
    finally {
        if ($sftpSession) { Remove-SFTPSession -SessionId $sftpSession.SessionId -ErrorAction SilentlyContinue | Out-Null }
        if ($sshSession)  { Remove-SSHSession  -SessionId $sshSession.SessionId  -ErrorAction SilentlyContinue | Out-Null }
        try { Disconnect-TAKServer -ErrorAction SilentlyContinue } catch { $null = $_ }
    }

    # ── Step 8: Summary ───────────────────────────────────────────────────────────
    Write-TAKBanner 'Onboarding Complete' 'Green'
    Write-Host ''
    Write-Host "  Team      : $TeamName ($($resolvedUserList.Count) users)"    -ForegroundColor White
    Write-Host "  Server    : https://$ServerHost`:$TakPort"                   -ForegroundColor White
    Write-Host "  Data pkgs : $resolvedOutputDir"                              -ForegroundColor White
    Write-Host ''

    Write-Host '  Users provisioned:' -ForegroundColor Cyan
    foreach ($u in $resolvedUserList) {
        $zipMark = if (-not $SkipDataPackages -and (Test-Path (Join-Path $resolvedOutputDir "$($u.Username).zip"))) { '[ZIP]' } else { '     ' }
        Write-Host "    $zipMark  $($u.Username)  ($($u.Role))"
    }

    Write-Host ''
    Write-Host '--- Distribution Checklist -------------------------------------------' -ForegroundColor Yellow
    Write-Host '  [ ] Send each user their .zip via an encrypted channel'
    Write-Host '      (Signal, encrypted USB — never plain email)'
    Write-Host '  [ ] ATAK (Android) : Files > Import Manager > Data Package'
    Write-Host '  [ ] WinTAK         : Tools > Data Package > Import'
    Write-Host '  [ ] iTAK (iOS)     : AirDrop .p12 + Apple Configurator'
    Write-Host "  [ ] Users change password at: https://$ServerHost`:$TakPort/userManagement"
    Write-Host "  [ ] Delete .\certs\$TeamName\ from this workstation after distribution"
    Write-Host ''
    Write-Host '--- Next Steps -------------------------------------------------------' -ForegroundColor Yellow
    Write-Host "  WebTAK admin : https://$ServerHost`:$TakPort"
    Write-Host "  CoT TLS port : $ServerHost`:$CotPort"
    Write-Host "  Cert enroll  : https://$ServerHost`:8446"
    Write-Host ''
    Write-Host 'Onboarding complete.' -ForegroundColor Green
}
