<#
.SYNOPSIS
    Returns $true if the current session is elevated (Administrator).

.DESCRIPTION
    Internal helper that wraps the WindowsPrincipal elevation check so it can
    be mocked in Pester unit tests without requiring a real elevated session.
#>
function Get-IsAdminSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
