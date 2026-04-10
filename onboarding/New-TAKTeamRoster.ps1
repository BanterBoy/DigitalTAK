#Requires -Version 7.0
# Thin wrapper — logic lives in TAKOnboarding\Public\New-TAKTeamRoster.ps1
Import-Module "$PSScriptRoot\..\TAKOnboarding\TAKOnboarding.psd1" -Force
New-TAKTeamRoster @args
