#Requires -Version 7.0
# Thin wrapper — logic lives in TAKOnboarding\Public\Invoke-TAKOnboarding.ps1
Import-Module "$PSScriptRoot\TAKOnboarding\TAKOnboarding.psd1" -Force
Invoke-TAKOnboarding -DeploymentRoot $PSScriptRoot @args
