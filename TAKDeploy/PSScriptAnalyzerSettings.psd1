@{
    # PSScriptAnalyzer settings for the TAKDeploy module.
    # Targets PowerShell 7.0+ — BOM is not required for UTF-8 files in PS 7.
    # Write-Host is intentional for interactive deployment wizard UI.
    # Plural noun is correct for Assert-HyperVPrerequisites (checks multiple items).
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
        'PSAvoidUsingWriteHost'
        'PSUseSingularNouns'
    )
}
