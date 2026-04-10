#Requires -Version 7.0
# Thin wrapper — logic lives in TAKDeploy\Public\Remove-TAKDeployment.ps1
Import-Module "$PSScriptRoot\TAKDeploy\TAKDeploy.psd1" -Force
Remove-TAKDeployment @args
