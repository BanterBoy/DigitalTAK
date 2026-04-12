#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Runs the DigitalTAK unit test suite for all PowerShell modules.

.DESCRIPTION
    Discovers and executes all *.Tests.ps1 files located in each module's Tests/
    sub-directory (TAKDeploy/Tests, TAKInstall/Tests, TAKServerPS/Tests).

    No live infrastructure is required — all external dependencies are mocked.
    Safe to run locally and in CI pipelines without Hyper-V or a TAK Server.

.PARAMETER Modules
    One or more module names to limit which tests are run.
    Valid values: TAKDeploy, TAKInstall, TAKServerPS.
    Defaults to all discovered modules.

.PARAMETER Tags
    One or more Pester tags to filter by.

.PARAMETER ExcludeTags
    One or more Pester tags to exclude.

.PARAMETER OutputPath
    Path for the NUnit XML test result file.
    Defaults to 'reports/TestResults-Unit.xml' in the repo root.

.PARAMETER PassThru
    Returns the Pester result object to the pipeline.

.EXAMPLE
    # Run all unit tests:
    .\Invoke-UnitTests.ps1

.EXAMPLE
    # Run only TAKDeploy tests with NUnit output:
    .\Invoke-UnitTests.ps1 -Modules TAKDeploy -OutputPath 'reports/unit.xml'

.EXAMPLE
    # CI usage:
    .\Invoke-UnitTests.ps1 -OutputPath 'reports/TestResults-Unit.xml'
    if ($LASTEXITCODE -ne 0) { exit 1 }
#>
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet('TAKDeploy', 'TAKInstall', 'TAKServerPS', 'TAKOnboarding')]
    [string[]] $Modules,

    [Parameter()]
    [string[]] $Tags,

    [Parameter()]
    [string[]] $ExcludeTags,

    [Parameter()]
    [string] $OutputPath,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve repo root ─────────────────────────────────────────────────────────
$repoRoot = $PSScriptRoot

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'reports' 'TestResults-Unit.xml'
}

$reportsDir = Split-Path $OutputPath
if (-not (Test-Path $reportsDir)) {
    $null = New-Item -ItemType Directory -Path $reportsDir -Force
}

# ── Discover test directories ─────────────────────────────────────────────────
$allModules = @('TAKDeploy', 'TAKInstall', 'TAKServerPS', 'TAKOnboarding')
$targetModules = if ($Modules) { $Modules } else { $allModules }

$testPaths = @()
foreach ($mod in $targetModules) {
    $testsDir = Join-Path $repoRoot $mod 'Tests'
    if (Test-Path $testsDir) {
        $testPaths += $testsDir
    }
    else {
        Write-Verbose "No Tests/ directory found for module '$mod' — skipped."
    }
}

if ($testPaths.Count -eq 0) {
    Write-Warning 'No unit test directories were found. Exiting.'
    exit 0
}

Write-Host ''
Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  DigitalTAK Unit Tests' -ForegroundColor Cyan
Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host "  Modules : $($targetModules -join ', ')"  -ForegroundColor Cyan
Write-Host "  Output  : $OutputPath"                   -ForegroundColor Cyan
Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ── Build Pester configuration ─────────────────────────────────────────────────
$pesterConfig = New-PesterConfiguration

$pesterConfig.Run.Path         = $testPaths
$pesterConfig.Run.PassThru     = $true
$pesterConfig.Output.Verbosity = 'Detailed'

$pesterConfig.TestResult.Enabled    = $true
$pesterConfig.TestResult.OutputPath = $OutputPath
$pesterConfig.TestResult.OutputFormat = 'NUnitXml'

if ($Tags)        { $pesterConfig.Filter.Tag        = $Tags        }
if ($ExcludeTags) { $pesterConfig.Filter.ExcludeTag = $ExcludeTags }

# ── Run tests ─────────────────────────────────────────────────────────────────
$result = Invoke-Pester -Configuration $pesterConfig

# ── Markdown summary ──────────────────────────────────────────────────────────
$summaryPath = Join-Path $reportsDir 'TestSummary-Unit.md'

$passed    = $result.PassedCount
$failed    = $result.FailedCount
$skipped   = $result.SkippedCount
$total     = $result.TotalCount
$duration  = [math]::Round($result.Duration.TotalSeconds, 2)
$status    = if ($failed -eq 0) { 'PASS' } else { 'FAIL' }
$timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$pathList  = ($testPaths | ForEach-Object { "- ``$_``" }) -join [System.Environment]::NewLine

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('# DigitalTAK Unit Test Summary')
$summaryLines.Add('')
$summaryLines.Add("**Run date:** $timestamp")
$summaryLines.Add("**Overall status:** $status")
$summaryLines.Add("**Duration:** ${duration}s")
$summaryLines.Add('')
$summaryLines.Add('## Results')
$summaryLines.Add('')
$summaryLines.Add('| Result  | Count |')
$summaryLines.Add('|---------|-------|')
$summaryLines.Add("| Passed  | $passed |")
$summaryLines.Add("| Failed  | $failed |")
$summaryLines.Add("| Skipped | $skipped |")
$summaryLines.Add("| Total   | $total |")
$summaryLines.Add('')
$summaryLines.Add('## Test Paths')
$summaryLines.Add('')
$summaryLines.Add($pathList)
$summaryLines.Add('')
$summaryLines.Add('## How to Run Locally')
$summaryLines.Add('')
$summaryLines.Add('```powershell')
$summaryLines.Add('# Run all unit tests')
$summaryLines.Add('.\Invoke-UnitTests.ps1')
$summaryLines.Add('')
$summaryLines.Add('# Run only TAKDeploy tests')
$summaryLines.Add('.\Invoke-UnitTests.ps1 -Modules TAKDeploy')
$summaryLines.Add('')
$summaryLines.Add('# With NUnit XML output')
$summaryLines.Add('.\Invoke-UnitTests.ps1 -OutputPath reports\TestResults-Unit.xml')
$summaryLines.Add('```')
$summaryLines.Add('')
$summaryLines.Add('## Prerequisites')
$summaryLines.Add('')
$summaryLines.Add('- PowerShell 7.0+')
$summaryLines.Add('- Pester 5.0+: `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force`')
$summaryLines.Add('- Hyper-V module (for TAKDeploy import): Windows host with Hyper-V role enabled, or Hyper-V RSAT tools')
$summaryLines.Add('')
$summaryLines.Add('> **Note:** No live TAK Server, Hyper-V VM, or SSH session is required. All external')
$summaryLines.Add('> dependencies are mocked inside the test files.')
$summaryLines.Add('')
$summaryLines.Add('## Next Test Priorities')
$summaryLines.Add('')
$summaryLines.Add('1. **Integration tests** — validate the full deployment pipeline against a live Hyper-V VM (see `tests/integration/`)')
$summaryLines.Add('2. **TAKInstall module** — unit tests for Install-TAKServer, New-TAKServerCertificate, etc.')
$summaryLines.Add('3. **TAKServerPS module** — unit tests for REST API user management cmdlets')
$summaryLines.Add('4. **Edge cases** — error paths in Assert-HyperVPrerequisites (missing modules, non-admin, missing ISO/RPM)')
$summaryLines.Add('5. **Negative path coverage** — Wait-TAKLinuxInstall with multiple NIC adapters and manual IP override')

$summaryLines | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host ''
Write-Host "Test summary written to: $summaryPath" -ForegroundColor Cyan
Write-Host ''

# ── Exit code ─────────────────────────────────────────────────────────────────
if ($PassThru) {
    $result
}

exit ($result.FailedCount -gt 0 ? 1 : 0)
