#Requires -Version 7.0
<#
.SYNOPSIS
    TAKServer PowerShell module — REST API wrapper for TAK Server 5.x.

.DESCRIPTION
    Provides cmdlets to manage TAK Server via its REST API, including session
    management, users, groups, missions, certificates, data feeds, inputs,
    subscriptions, video connections, and more.

    Begin a session with Connect-TAKServer, then use any other cmdlet. End with
    Disconnect-TAKServer.
#>

# Module-scoped session state — shared across all functions.
$script:TAKSession = $null

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }
