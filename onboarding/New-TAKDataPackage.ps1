#Requires -Version 7.0
# Thin wrapper — logic lives in TAKOnboarding\Public\New-TAKDataPackage.ps1
Import-Module "$PSScriptRoot\..\TAKOnboarding\TAKOnboarding.psd1" -Force
New-TAKDataPackage @args
