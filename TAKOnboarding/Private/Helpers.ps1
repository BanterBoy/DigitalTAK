# Private helpers for TAKOnboarding module.
# These are module-scoped and not exported.

function Write-TAKBanner {
    param([string] $Text, [string] $Color = 'Cyan')
    $line = '-' * 70
    Write-Host ''
    Write-Host $line -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-TAKStep {
    param([int] $Number, [string] $Text)
    Write-Host ''
    Write-Host "STEP $Number  $Text" -ForegroundColor Yellow
    Write-Host ('-' * 50) -ForegroundColor DarkGray
}

function Write-TAKOk   { param([string] $Msg) Write-Host "  [OK]    $Msg" -ForegroundColor Green   }
function Write-TAKSkip { param([string] $Msg) Write-Host "  [SKIP]  $Msg" -ForegroundColor DarkGray }
function Write-TAKWarn { param([string] $Msg) Write-Host "  [WARN]  $Msg" -ForegroundColor Yellow  }
function Write-TAKFail { param([string] $Msg) Write-Host "  [FAIL]  $Msg" -ForegroundColor Red     }

function ConvertFrom-TAKSecureString {
    param([System.Security.SecureString] $Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Find-TAKKeytool {
    $kt = Get-Command keytool -ErrorAction SilentlyContinue
    if ($kt) { return $kt.Source }
    foreach ($base in $env:JAVA_HOME, 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java') {
        if ($base -and (Test-Path $base)) {
            $found = Get-ChildItem -Path $base -Filter keytool.exe -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return $null
}

function Invoke-TAKSSHCommand {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)] [string] $Command,
        [string] $Description = $Command,
        [int]    $TimeoutSec  = 60
    )
    Write-Verbose "SSH: $Description"
    $result = Invoke-SSHCommand -SessionId $Session.SessionId -Command $Command -TimeOut $TimeoutSec
    if ($result.ExitStatus -ne 0) {
        throw "SSH command failed (exit $($result.ExitStatus)): $Description`nOutput: $($result.Output -join "`n")"
    }
    return $result.Output
}

function Build-TAKUserList {
    param([string] $Team, [int] $Size)
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()
    $list.Add([PSCustomObject]@{ Username = "${Team}-lead";      Role = 'Team Lead';      ExtraGroups = @() })
    $list.Add([PSCustomObject]@{ Username = "${Team}-asst-lead"; Role = 'Assistant Lead'; ExtraGroups = @() })
    $opCount = $Size - 2
    foreach ($i in 1..$opCount) {
        $seq = $i.ToString().PadLeft(2, '0')
        $list.Add([PSCustomObject]@{ Username = "${Team}-op-${seq}"; Role = 'Operator'; ExtraGroups = @() })
    }
    return $list
}

function Import-TAKRosterFile {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $TeamFilter = ''
    )
    $ext  = [System.IO.Path]::GetExtension($Path).ToLower()
    $rows = switch ($ext) {
        '.csv'  { Import-Csv -Path $Path }
        '.json' { Get-Content -Raw $Path | ConvertFrom-Json }
        default { throw "Unsupported roster file type '$ext'. Use .csv or .json." }
    }
    if (-not $rows -or $rows.Count -eq 0) {
        throw "Roster file '$Path' is empty or could not be parsed."
    }
    $hasTeamCol = $rows[0].PSObject.Properties.Name -match '^team$'
    if ($hasTeamCol -and $TeamFilter) {
        $rows = @($rows | Where-Object {
            ($_.PSObject.Properties | Where-Object { $_.Name -match '^team$' } | Select-Object -First 1).Value -eq $TeamFilter
        })
        if ($rows.Count -eq 0) {
            throw "No rows in '$Path' match team '$TeamFilter'. Check the Team column values."
        }
    }
    $validRoles = 'Team Lead', 'Assistant Lead', 'Operator'
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($row in $rows) {
        $username = ($row.PSObject.Properties | Where-Object { $_.Name -match '^username$' } | Select-Object -First 1).Value
        $role     = ($row.PSObject.Properties | Where-Object { $_.Name -match '^role$'     } | Select-Object -First 1).Value
        if ([string]::IsNullOrWhiteSpace($username)) { throw "Roster row missing 'Username': $($row | ConvertTo-Json -Compress)" }
        if ([string]::IsNullOrWhiteSpace($role))     { throw "Roster entry '$username' missing 'Role'." }
        if ($role -notin $validRoles)                { throw "Roster entry '$username' has unrecognised role '$role'. Valid: $($validRoles -join ', ')" }
        if ($username -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') { throw "Username '$username' contains invalid characters." }
        $extraProp   = ($row.PSObject.Properties | Where-Object { $_.Name -match '^extragroups?$' } | Select-Object -First 1).Value
        $extraGroups = if ($extraProp -is [System.Collections.IEnumerable] -and $extraProp -isnot [string]) {
            @($extraProp | Where-Object { $_ })
        } elseif ($extraProp) {
            @($extraProp.ToString().Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else { @() }
        $list.Add([PSCustomObject]@{ Username = $username.Trim(); Role = $role.Trim(); ExtraGroups = $extraGroups })
    }
    return $list
}
