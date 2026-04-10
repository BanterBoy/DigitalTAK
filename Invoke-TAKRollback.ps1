#Requires -Version 7.0
# Thin wrapper — logic lives in TAKDeploy\Public\Invoke-TAKRollback.ps1
Import-Module "$PSScriptRoot\TAKDeploy\TAKDeploy.psd1" -Force
Invoke-TAKRollback @args
