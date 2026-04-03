#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Runs the TakServerPS E2E test suite against a live TAK Server deployment.

.DESCRIPTION
    Executes all E2E tests in tests/e2e/ and produces:
      - A JUnit-compatible XML report  (reports/TestResults-E2E.xml)
      - A Markdown summary report      (reports/TestResults-E2E.md)

    Tests skip automatically when TAK_INTEGRATION_HOST is not set, so this
    script is safe to run in any environment (unit-test CI passes, E2E tests
    are simply marked as skipped).

    Required environment variables:
        TAK_INTEGRATION_HOST  - IP address or hostname of the TAK Server VM
        TAK_CERT_PASS         - PKCS#12 certificate password (no default)

    Optional environment variables:
        TAK_API_PORT          - HTTPS API port (default: 8443)
        TAK_COT_PORT          - CoT TCP/SSL port (default: 8089)
        TAK_SENDER_UID        - CoT sender UID (default: Pester-E2E-Test)
        TAK_SENDER_CALLSIGN   - CoT sender callsign (default: Pester-E2E)
        TAK_GROUP             - TAK group for test clients (default: Cyan)

.PARAMETER Tags
    One or more Pester tags to filter tests.
    Available tags: E2E, ServerStatus, CertAuth, CoT, Tracking, GeoChat, Mission, DataPackage, Negative, Security

.PARAMETER ExcludeTags
    Pester tags to exclude.

.PARAMETER XmlOutputPath
    Path for the JUnit XML result file.
    Defaults to reports/TestResults-E2E.xml in the repo root.

.PARAMETER MarkdownOutputPath
    Path for the Markdown summary report.
    Defaults to reports/TestResults-E2E.md in the repo root.

.PARAMETER PassThru
    Returns the Pester result object to the pipeline.

.EXAMPLE
    # Full E2E run:
    $env:TAK_INTEGRATION_HOST = '192.168.1.50'
    $env:TAK_CERT_PASS        = 'MySecret123'
    .\Invoke-E2ETests.ps1

.EXAMPLE
    # Only run connectivity and auth tests:
    .\Invoke-E2ETests.ps1 -Tags ServerStatus, CertAuth

.EXAMPLE
    # Skip negative/security tests:
    .\Invoke-E2ETests.ps1 -ExcludeTags Negative, Security

.EXAMPLE
    # CI-style with custom output paths:
    .\Invoke-E2ETests.ps1 -XmlOutputPath 'artifacts/e2e.xml' -MarkdownOutputPath 'artifacts/e2e.md' -PassThru
#>

[CmdletBinding()]
param (
    [string[]] $Tags,
    [string[]] $ExcludeTags,
    [string]   $XmlOutputPath,
    [string]   $MarkdownOutputPath,
    [switch]   $PassThru
)

$ErrorActionPreference = 'Stop'

# Resolve default output paths here rather than in the param defaults so that
# Join-Path works correctly when $PSScriptRoot is empty (e.g. pwsh -Command).
$_root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $XmlOutputPath)      { $XmlOutputPath      = Join-Path $_root 'reports' 'TestResults-E2E.xml' }
if (-not $MarkdownOutputPath) { $MarkdownOutputPath = Join-Path $_root 'reports' 'TestResults-E2E.md' }

# ── Banner ────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  TakServerPS E2E Test Suite' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$host_ = $env:TAK_INTEGRATION_HOST
if ([string]::IsNullOrWhiteSpace($host_)) {
    Write-Host '  [WARN] TAK_INTEGRATION_HOST is not set.' -ForegroundColor Yellow
    Write-Host '         All E2E tests will be skipped.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  To run against a live deployment, set:' -ForegroundColor DarkGray
    Write-Host '      $env:TAK_INTEGRATION_HOST = "<VM IP or hostname>"' -ForegroundColor DarkGray
    Write-Host '      $env:TAK_CERT_PASS        = "<cert password>"' -ForegroundColor DarkGray
    Write-Host ''
} else {
    Write-Host "  Target host : $host_" -ForegroundColor Green
    Write-Host "  API port    : $($env:TAK_API_PORT ?? '8443')" -ForegroundColor Green
    Write-Host "  CoT port    : $($env:TAK_COT_PORT ?? '8089')" -ForegroundColor Green
    Write-Host "  XML report  : $XmlOutputPath" -ForegroundColor Green
    Write-Host "  MD report   : $MarkdownOutputPath" -ForegroundColor Green
    Write-Host ''
}

# ── Ensure reports directory ──────────────────────────────────────────────────

$reportsDir = Split-Path $XmlOutputPath -Parent
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

# ── Pester configuration ──────────────────────────────────────────────────────

$config = New-PesterConfiguration

$config.Run.Path         = Join-Path $_root 'tests' 'e2e'
$config.Run.Exit         = $false
$config.Output.Verbosity = 'Detailed'

# Use JUnitXml when available (Pester 5.4+), else fall back to NUnit2.5
$pesterVersion = (Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
$xmlFormat = if ($pesterVersion -ge [version]'5.4.0') { 'JUnitXml' } else { 'NUnit2.5' }

$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = $XmlOutputPath
$config.TestResult.OutputFormat = $xmlFormat

Write-Host "  XML format  : $xmlFormat (Pester $pesterVersion)" -ForegroundColor DarkGray
Write-Host ''

if ($Tags)        { $config.Filter.Tag        = $Tags }
if ($ExcludeTags) { $config.Filter.ExcludeTag = $ExcludeTags }

# ── Run ───────────────────────────────────────────────────────────────────────

$config.Run.PassThru = $true   # Must be in config, not on Invoke-Pester when using -Configuration

$startTime = [datetime]::UtcNow
$result    = Invoke-Pester -Configuration $config
$elapsed   = ([datetime]::UtcNow - $startTime).TotalSeconds

# ── Console summary ───────────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
$passedCount  = $result.PassedCount
$failedCount  = $result.FailedCount
$skippedCount = $result.SkippedCount
$totalCount   = $result.TotalCount

$summaryColor = if ($failedCount -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Results : $passedCount passed / $failedCount failed / $skippedCount skipped (of $totalCount)" -ForegroundColor $summaryColor
Write-Host "  Duration: $([math]::Round($elapsed, 1))s" -ForegroundColor DarkGray
Write-Host "  XML     : $XmlOutputPath" -ForegroundColor DarkGray
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ── Markdown summary ──────────────────────────────────────────────────────────

function ConvertTo-TAKMarkdownReport {
    param(
        [Parameter(Mandatory)] $PesterResult,
        [Parameter(Mandatory)] [string] $OutputPath,
        [double] $ElapsedSeconds,
        [string] $TargetHost
    )

    $passed  = $PesterResult.PassedCount
    $failed  = $PesterResult.FailedCount
    $skipped = $PesterResult.SkippedCount
    $total   = $PesterResult.TotalCount
    $status  = if ($failed -eq 0) { ':white_check_mark: PASS' } else { ':x: FAIL' }
    $runAt   = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# TakServerPS E2E Test Results")
    $lines.Add("")
    $lines.Add("| Field | Value |")
    $lines.Add("|-------|-------|")
    $lines.Add("| **Status** | $status |")
    $lines.Add("| **Run at** | $runAt |")
    $lines.Add("| **Target** | $($TargetHost ?? '(skipped — no host set)') |")
    $lines.Add("| **Duration** | $([math]::Round($ElapsedSeconds, 1))s |")
    $lines.Add("| **Total** | $total |")
    $lines.Add("| **Passed** | $passed |")
    $lines.Add("| **Failed** | $failed |")
    $lines.Add("| **Skipped** | $skipped |")
    $lines.Add("")

    # Per-container (Describe block) breakdown
    $lines.Add("## Results by Test Group")
    $lines.Add("")
    $lines.Add("| Test Group | Passed | Failed | Skipped |")
    $lines.Add("|------------|--------|--------|---------|")

    foreach ($container in $PesterResult.Containers) {
        foreach ($block in $container.Blocks) {
            $bPassed  = ($block.Tests | Where-Object { $_.Result -eq 'Passed'  }).Count
            $bFailed  = ($block.Tests | Where-Object { $_.Result -eq 'Failed'  }).Count
            $bSkipped = ($block.Tests | Where-Object { $_.Result -eq 'Skipped' }).Count
            $icon     = if ($bFailed -gt 0) { ':x:' } elseif ($bPassed -gt 0) { ':white_check_mark:' } else { ':fast_forward:' }
            $lines.Add("| $icon $($block.Name) | $bPassed | $bFailed | $bSkipped |")
        }
    }
    $lines.Add("")

    # Failed tests detail
    $allFailed = $PesterResult.Containers.Blocks.Tests | Where-Object { $_.Result -eq 'Failed' }
    if ($allFailed) {
        $lines.Add("## Failed Tests")
        $lines.Add("")
        foreach ($t in $allFailed) {
            $lines.Add("### :x: $($t.Name)")
            $lines.Add("")
            $lines.Add("**Block:** $($t.Block.Name)")
            $lines.Add("")
            if ($t.ErrorRecord) {
                $lines.Add("**Error:**")
                $lines.Add("```")
                $lines.Add($t.ErrorRecord.Exception.Message)
                $lines.Add("```")
            }
            $lines.Add("")
        }
    }

    # Skipped tests (grouped)
    $allSkipped = $PesterResult.Containers.Blocks.Tests | Where-Object { $_.Result -eq 'Skipped' }
    if ($allSkipped -and $skipped -gt 0) {
        $lines.Add("## Skipped Tests ($skipped)")
        $lines.Add("")
        $lines.Add("> Skipped tests indicate missing environment variables.")
        $lines.Add("> Set \`TAK_INTEGRATION_HOST\` and \`TAK_CERT_PASS\` to run against a live server.")
        $lines.Add("")
        foreach ($t in $allSkipped | Select-Object -First 10) {
            $lines.Add("- $($t.Block.Name) › $($t.Name)")
        }
        if ($allSkipped.Count -gt 10) {
            $lines.Add("- *(and $($allSkipped.Count - 10) more…)*")
        }
        $lines.Add("")
    }

    $lines.Add("---")
    $lines.Add("*Generated by [Invoke-E2ETests.ps1](../../Invoke-E2ETests.ps1)*")

    [System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.Encoding]::UTF8)
    Write-Host "  Markdown: $OutputPath" -ForegroundColor DarkGray
}

ConvertTo-TAKMarkdownReport `
    -PesterResult    $result `
    -OutputPath      $MarkdownOutputPath `
    -ElapsedSeconds  $elapsed `
    -TargetHost      $env:TAK_INTEGRATION_HOST

Write-Host ''

if ($PassThru) { return $result }

if ($failedCount -gt 0) { exit 1 }
