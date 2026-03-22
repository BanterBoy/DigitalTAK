#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Syncs TXTScripts/*.txt mirrors from their InstallShellScripts/*.sh sources.

.DESCRIPTION
    Each .sh file in InstallShellScripts/ must have a byte-identical .txt
    counterpart in TXTScripts/.  Run this script after every .sh edit to keep
    the mirrors in sync.  CI enforces the same constraint via the txt-sync job.

.EXAMPLE
    PS> ./Sync-TXTMirrors.ps1

    Syncs all .sh files to their .txt counterparts and reports the result.

.EXAMPLE
    PS> ./Sync-TXTMirrors.ps1 -WhatIf

    Shows which files would be updated without writing anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param ()

$shDir  = Join-Path $PSScriptRoot 'InstallShellScripts'
$txtDir = Join-Path $PSScriptRoot 'TXTScripts'

if (-not (Test-Path $txtDir)) {
    New-Item -ItemType Directory -Path $txtDir | Out-Null
    Write-Verbose "Created TXTScripts/ directory."
}

$synced  = 0
$skipped = 0

foreach ($sh in Get-ChildItem -Path $shDir -Filter '*.sh') {
    $txtPath = Join-Path $txtDir ($sh.BaseName + '.txt')

    if ($PSCmdlet.ShouldProcess($sh.Name, "Sync to $(Split-Path $txtPath -Leaf)")) {
        Copy-Item -Path $sh.FullName -Destination $txtPath -Force
        Write-Host "  Synced: $($sh.Name)  ->  $(Split-Path $txtPath -Leaf)"
        $synced++
    }
    else {
        $skipped++
    }
}

Write-Host ""
Write-Host "Done. $synced file(s) synced, $skipped skipped."
