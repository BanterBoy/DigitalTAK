#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Runs the DigitalTAK integration test suite against a live TAK Server deployment.

.DESCRIPTION
    Executes all integration tests in the tests/integration/ directory.
    Tests are skipped automatically if the required environment variables are
    not set, so this script is safe to run in any environment.

    Integration tests require:
      - A running TAK Server VM (deployed via Deploy-TAKServer.ps1)
      - Posh-SSH module (Install-Module Posh-SSH)
      - TAKServerPS module (included in this repo)

    Required environment variables:
        TAK_INTEGRATION_HOST  - IP address or hostname of the TAK Server VM

    Optional environment variables:
        TAK_SSH_USER          - SSH username (default: atak)
        TAK_SSH_PASS          - SSH password (plain text — use only in secure environments)
        TAK_VM_NAME           - Hyper-V VM name for VM-level tests (default: TAKServer)
        TAK_CERT_PASS         - PKCS#12 certificate password (required — no default)
        TAK_API_PORT          - TAK Server HTTPS port (default: 8443)
        TAK_ENROLL_PORT       - Certificate enrollment port (default: 8446)
        TAK_COT_PORT          - CoT TCP port (default: 8089)
        TAK_API_USER          - Fallback basic-auth user for user-management tests
        TAK_API_PASS          - Fallback basic-auth password

.PARAMETER Tags
    One or more Pester tags to filter tests. Available tags:
        Integration, VM, OS, TAKServer, Certificates, API, UserManagement, Security

.PARAMETER ExcludeTags
    Pester tags to exclude (e.g. 'VM' to skip Hyper-V host-only tests).

.PARAMETER OutputPath
    Path for the NUnit XML test result file. Defaults to
    reports/TestResults-Integration.xml in the repo root.

.PARAMETER PassThru
    Returns the Pester result object to the pipeline.

.EXAMPLE
    # Full integration run against a local deployment:
    $env:TAK_INTEGRATION_HOST = '192.168.1.50'
    $env:TAK_SSH_PASS         = 'IamGroot.3742'
    .\Invoke-IntegrationTests.ps1

.EXAMPLE
    # Skip Hyper-V VM tests (e.g. when running from a machine without Hyper-V):
    .\Invoke-IntegrationTests.ps1 -ExcludeTags VM

.EXAMPLE
    # Run only health and certificate tests:
    .\Invoke-IntegrationTests.ps1 -Tags TAKServer, Certificates

.EXAMPLE
    # CI-style run with XML output:
    .\Invoke-IntegrationTests.ps1 -OutputPath 'TestResults-Integration.xml' -PassThru
#>

[CmdletBinding()]
param (
    [string[]] $Tags,
    [string[]] $ExcludeTags,
    [string]   $OutputPath,
    [switch]   $PassThru
)

$ErrorActionPreference = 'Stop'

# Resolve default output path here rather than in the param default so that
# Join-Path works correctly when $PSScriptRoot is empty (e.g. pwsh -Command).
$_root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $OutputPath) { $OutputPath = Join-Path $_root 'reports' 'TestResults-Integration.xml' }

# ── Prerequisites check ───────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  DigitalTAK Integration Test Suite' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$host_ = $env:TAK_INTEGRATION_HOST
if ([string]::IsNullOrWhiteSpace($host_)) {
    Write-Host '  [WARN] TAK_INTEGRATION_HOST is not set.' -ForegroundColor Yellow
    Write-Host '         All integration tests will be skipped.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  To run against a live deployment, set:' -ForegroundColor DarkGray
    Write-Host '      $env:TAK_INTEGRATION_HOST = "<VM IP>"' -ForegroundColor DarkGray
    Write-Host '      $env:TAK_SSH_PASS         = "<SSH password>"' -ForegroundColor DarkGray
    Write-Host ''
} else {
    Write-Host "  Target host : $host_" -ForegroundColor Green
    Write-Host "  SSH user    : $($env:TAK_SSH_USER ?? 'atak')" -ForegroundColor Green
    Write-Host "  VM name     : $($env:TAK_VM_NAME ?? 'TAKServer')" -ForegroundColor Green
    Write-Host ''
}

# Ensure reports directory exists
$reportsDir = Join-Path $_root 'reports'
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}

# ── Pester configuration ──────────────────────────────────────────────────────

$config = New-PesterConfiguration

$config.Run.Path            = Join-Path $_root 'tests' 'integration'
$config.Run.Exit            = $false   # Do not exit process — caller handles this
$config.Run.PassThru        = $true    # PassThru must be set in config, not on Invoke-Pester -Configuration
$config.Output.Verbosity    = 'Detailed'
$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = $OutputPath
$config.TestResult.OutputFormat = 'NUnit2.5'

if ($Tags) {
    $config.Filter.Tag = $Tags
}

if ($ExcludeTags) {
    $config.Filter.ExcludeTag = $ExcludeTags
}

# ── Run ───────────────────────────────────────────────────────────────────────

$result = Invoke-Pester -Configuration $config

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
$passedCount  = $result.PassedCount
$failedCount  = $result.FailedCount
$skippedCount = $result.SkippedCount
$totalCount   = $result.TotalCount

$summaryColor = if ($failedCount -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Results: $passedCount passed / $failedCount failed / $skippedCount skipped (of $totalCount)" -ForegroundColor $summaryColor
Write-Host "  Report : $OutputPath" -ForegroundColor DarkGray
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

if ($PassThru) {
    return $result
}

# Exit with non-zero code if any tests failed (useful for CI)
if ($failedCount -gt 0) {
    exit 1
}
