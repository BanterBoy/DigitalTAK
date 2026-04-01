@{
    # PSScriptAnalyzer settings for root-level deployment orchestration scripts.
    # These are standalone interactive console scripts, not module cmdlets.
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'                    # UTF-8 without BOM is fine in PS 7
        'PSAvoidUsingWriteHost'                            # Interactive console output is intentional
        'PSAvoidUsingConvertToSecureStringWithPlainText'   # atakatak is the fixed TAK Server default PFX password, documented upstream
        'PSUseShouldProcessForStateChangingFunctions'      # Standalone scripts, not module cmdlets; ShouldProcess not applicable
        'PSAvoidUsingPositionalParameters'                 # Join-Path positional use is clear in context
    )
}
