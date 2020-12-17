
function Import-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Imports a PowerShell module.

    .DESCRIPTION
    The `Import-WhiskeyPowerShellModule` function imports a PowerShell module that is needed/used by a Whiskey task. Since Whiskey tasks all run in the module's scope, the imported modules are imported into the global scope. If a module with the same name is currently loaded, it is removed and re-imported.

    If the `InstalledGlobally` switch is set, the module must be installed globally and the path to the module must exist in the PSModulePath environment variable. If multiple versions of the module exist, the latest version will be imported unless a version is provided.

    If the `InstalledGlobally` switch is not set, the module must be installed in Whiskey's PowerShell modules directory. Use the `RequiresTool` attribute on a task to have Whiskey install a module in this directory or the `GetPowerShellModule` task to install a module in the appropriate place.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -InstalledGlobally

    Demonstrates how to use this method to import the latest version of a globally installed module.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -Version '0.2.0' -InstalledGlobally

    Demonstrates how to use this method to a import specific version a globally installed module.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -Version '0.*' -InstalledGlobally

    Demonstrates that you can use wildcards to import the latest minor version of a globally installed module.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -PSModulesRoot 'Path/To/Build/Root'

    Demonstrates how to use this method to import a module that is installed locally at `PSModulesRoot`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The module names to import.
        [String]$Name,

        # The version of the module to import.
        [String]$Version,

        [Parameter(Mandatory)]
        # The path to the build root, where the PSModules directory can be found. Must be included to import a locally installed module.
        [String]$PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $numErrorsBefore = $Global:Error.Count
    $foundModule = $false
    try
    {
        $foundModule = & {
            $VerbosePreference = 'SilentlyContinue'
            $module = Get-WhiskeyPSModule -Name $Name -Version $Version -PSModulesRoot $PSModulesRoot
            if( -not $module )
            {
                return $false
            }

            $loadedModules = Get-Module -Name $Name
            $loadedModules |
                Where-Object 'Version' -ne $module.Version |
                Remove-Module -Verbose:$false -WhatIf:$false -Force

            if( ($loadedModules | Where-Object 'Version' -eq $module.Version) )
            {
                Write-WhiskeyDebug -Message ("Module $($Name) $($module.Version) already loaded.")
                return $true
            }

            $module | Import-Module -Global -ErrorAction Stop -Verbose:$false
            return $true
        } 4> $null
    }
    finally
    {
        # Some modules (...cough...PowerShellGet...cough...) write silent errors during import. This causes our 
        # tests to fail. I know this is a little extreme.
        $numToRemove = $Global:Error.Count - $numErrorsBefore
        for( $idx = 0; $idx -lt $numToRemove; $idx++ )
        {
            $Global:Error.RemoveAt(0)
        }
    }

    if( -not $foundModule )
    {
        $versionDesc = ''
        if( $Version )
        {
            $versionDesc = " $($Version)"
        }
        $msg = "Unable to import module ""$($Name)""$($versionDesc): that module isn't installed. To install a module, " +
               'use the "GetPowerShellModule" task.'
        Write-WhiskeyError -Message $msg
    }
}
