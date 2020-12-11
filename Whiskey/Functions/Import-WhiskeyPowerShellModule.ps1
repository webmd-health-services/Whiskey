
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

        # The version of the module to import. Only referenced when importing a globally installed module.
        [String]$Version,

        # The path to the build root, where the PSModules directory can be found. Must be included to import a locally installed module.
        [String]$PSModulesRoot,

        # Import the globally installed version of the module.
        [switch]$InstalledGlobally
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    & {
        $VerbosePreference = 'SilentlyContinue'
        Get-Module -Name $Name | Remove-Module -Force -WhatIf:$false
    }

    $module = $null

    if($InstalledGlobally)
    {
        $globalModule = Test-GlobalPowerShellModule -Name $Name -Version $Version
        if($globalModule.Found)
        {
            $module = $globalModule.Path
        }
    }
    elseif ($PSModulesRoot)
    {
        $moduleDir = Join-Path -Path $PSModulesRoot -ChildPath $Name
        if ( Test-Path -Path $moduleDir -PathType Container )
        {
            $module = $moduleDir
        }
    }

    if( $module )
    {
        $relativeModulePath = Resolve-Path -Path $module -Relative -ErrorAction Ignore
        Write-WhiskeyDebug -Message ('PSModuleAutoLoadingPreference = "{0}"' -f $PSModuleAutoLoadingPreference)
        Write-WhiskeyVerbose -Message ('Importing PowerShell module "{0}" from "{1}".' -f $Name,$relativeModulePath)
        $errorsBefore = $Global:Error.Clone()
        $Global:Error.Clear()
        try
        {
            & {
                $VerbosePreference = 'SilentlyContinue'
                Import-Module -Name $module -Global -Force -ErrorAction Stop -Verbose:$false
            } 4> $null
        }
        finally
        {
            # Some modules (...cough...PowerShellGet...cough...) write silent errors during import. This causes our 
            # tests to fail. I know this is a little extreme.
            $Global:Error.Clear()
            $Global:Error.AddRange($errorsBefore)
        }
        return
    }
    else
    {
        if($InstalledGlobally)
        {
            if($Version)
            {
                Write-WhiskeyError -Message ('Version "{0}" of module "{1}" does not exist in the global scope. Make sure the module is installed and the path to the module is listed in the PSModulePath environment variable.' -f $Version,$Name) -ErrorAction Stop
            }
            else
            {
                Write-WhiskeyError -Message ('Module "{0}" does not exist in the global scope. Make sure the module is installed and the path to the module is listed in the PSModulePath environment variable.' -f $Name) -ErrorAction Stop
            }

        }
        else
        {
            Write-WhiskeyError -Message ('Module "{0}" does not exist in the local scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.' -f $Name) -ErrorAction Stop
        }
    }
}
