<#
.SYNOPSIS
    Creates or replaces a Device Profile on a connected TAK Server and uploads a data-package ZIP.

.DESCRIPTION
    Automates the three-step TAK Server Device Profile API workflow:

      1. Create the profile record  — POST /Marti/api/device/profile/{Name}
      2. Set type, active flag, and group scoping — PUT /Marti/api/device/profile/{Name}
      3. Upload the mission-package ZIP — PUT /Marti/api/device/profile/{Name}/file?filename=…

    Device Profiles are pushed automatically to ATAK/WinTAK clients when they connect or
    enroll, pre-configuring server connections, map sources, and preferences without any
    manual import step.

    If a profile with the given name already exists it is deleted before re-creation so
    the cmdlet is idempotent.

    Requires an active session from Connect-TAKServer.

.PARAMETER Name
    Unique display name for the Device Profile (e.g. 'bravo-enrollment').
    Must not contain characters that are invalid in a URL path segment.

.PARAMETER ProfileType
    When the profile is applied to connected clients.
      Enrollment — pushed when a client auto-enrolls via port 8446 (default).
      Connection  — pushed on every connection to the server.

.PARAMETER ZipPath
    Path to the ATAK mission-package ZIP that will be uploaded to the profile.
    Use New-TAKEnrollmentPackage to build the ZIP.

.PARAMETER Groups
    One or more TAK group names that the profile is scoped to.
    Clients whose certificate identity belongs to one of these groups will
    receive the profile.  If omitted the profile applies to all groups.

.PARAMETER Active
    Whether the profile is active.  Defaults to $true.

.EXAMPLE
    PS> Publish-TAKDeviceProfile -Name 'bravo-enrollment' -ZipPath .\dist\bravo\bravo-enrollment.zip -Groups 'bravo'

    Creates an Enrollment profile scoped to the bravo group and uploads the ZIP.

.EXAMPLE
    PS> Publish-TAKDeviceProfile -Name 'global-config' -ProfileType Connection -ZipPath .\dist\global.zip

    Creates a Connection profile with no group filter (applies to all clients).

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
    The TAK Server Device Profile API uses three separate HTTP calls — the cmdlet
    handles all of them transparently.
#>
function Publish-TAKDeviceProfile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [ValidateSet('Enrollment', 'Connection')]
        [string] $ProfileType = 'Enrollment',

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $ZipPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Groups,

        [Parameter()]
        [bool] $Active = $true
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $script:TAKSession) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                'Not connected to a TAK Server. Run Connect-TAKServer first.'
            ),
            'TAKNotConnected',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # ── Build shared IRM parameters from the active session ───────────────────
    $baseUrl = $script:TAKSession.BaseUrl.TrimEnd('/')
    $irmBase  = @{}

    if ($script:TAKSession.Certificate) {
        $irmBase['Certificate'] = $script:TAKSession.Certificate
    }
    elseif ($script:TAKSession.Token) {
        $irmBase['Authentication'] = 'Bearer'
        $irmBase['Token']          = $script:TAKSession.Token
    }
    elseif ($script:TAKSession.Credential) {
        $irmBase['Authentication'] = 'Basic'
        $irmBase['Credential']     = $script:TAKSession.Credential
    }

    if ($script:TAKSession.SkipCertCheck) {
        $irmBase['SkipCertificateCheck'] = $true
    }

    $encodedName = [Uri]::EscapeDataString($Name)

    if (-not $PSCmdlet.ShouldProcess($Name, "Publish TAK Device Profile ($ProfileType)")) {
        return
    }

    # ── Step 0: Delete existing profile with the same name (idempotency) ─────
    try {
        $existing = Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$encodedName" `
                        -Method Get @irmBase -ErrorAction Stop
        $existingData = if ($existing.PSObject.Properties.Name -contains 'data') { $existing.data } else { $existing }
        if ($null -ne $existingData -and $existingData.PSObject.Properties.Name -contains 'id') {
            Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$($existingData.id)" `
                -Method Delete @irmBase -ErrorAction SilentlyContinue | Out-Null
            Write-Verbose "Deleted existing profile '$Name' (id=$($existingData.id))"
        }
    }
    catch {
        # Profile does not exist — fine, continue with creation
        Write-Verbose "No existing profile named '$Name'"
    }

    # ── Step 1: Create the profile record ────────────────────────────────────
    Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$($encodedName)?group=__ANON__" `
        -Method Post @irmBase -ErrorAction Stop | Out-Null
    Write-Verbose "Created profile record '$Name'"

    # ── Step 2: GET the created profile (need id/updated/tool for the PUT body) ─
    $created = Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$encodedName" `
                   -Method Get @irmBase -ErrorAction Stop
    $profileData = if ($created.PSObject.Properties.Name -contains 'data') { $created.data } else { $created }

    # Build a clean update body — do not mutate the server-returned object.
    # Set-StrictMode -Version Latest prevents setting properties that do not exist
    # on a PSCustomObject, and the server may not return all fields on creation.
    $updateBody = [ordered]@{
        id               = $profileData.id
        name             = $Name
        type             = $ProfileType
        active           = $Active
        applyOnEnrollment = ($ProfileType -eq 'Enrollment')
        applyOnConnect   = ($ProfileType -eq 'Connection')
        groups           = if ($Groups) { @($Groups) } else { @() }
    }

    Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$encodedName" `
        -Method Put -Body ($updateBody | ConvertTo-Json -Compress) `
        -ContentType 'application/json' @irmBase -ErrorAction Stop | Out-Null
    Write-Verbose "Updated profile '$Name' — type=$ProfileType, groups=$($Groups -join ',')"

    # ── Step 3: Upload the ZIP as raw bytes ───────────────────────────────────
    $resolvedZip  = (Resolve-Path $ZipPath).Path
    $zipBytes     = [System.IO.File]::ReadAllBytes($resolvedZip)
    $zipFileName  = [Uri]::EscapeDataString([System.IO.Path]::GetFileName($resolvedZip))

    Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$encodedName/file?filename=$zipFileName" `
        -Method Put -Body $zipBytes -ContentType 'application/octet-stream' `
        @irmBase -ErrorAction Stop | Out-Null
    Write-Verbose "Uploaded '$zipFileName' to profile '$Name'"

    # ── Step 4: Return the final profile state ────────────────────────────────
    $resp = Invoke-RestMethod -Uri "$baseUrl/Marti/api/device/profile/$encodedName" `
                -Method Get @irmBase -ErrorAction Stop
    if ($resp.PSObject.Properties.Name -contains 'data') { $resp.data } else { $resp }
}
