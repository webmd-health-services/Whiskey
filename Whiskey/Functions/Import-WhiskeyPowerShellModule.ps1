
function Import-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Imports a PowerShell module.

    .DESCRIPTION
    The `Import-WhiskeyPowerShellModule` function imports a PowerShell module that is needed/used by a Whiskey task. Since Whiskey tasks all run in the module's scope, the imported modules are imported into the global scope. If a module with the same name is currently loaded, it is removed and re-imported.

    The module must be installed in Whiskey's PowerShell modules directory. Use the `RequiresTool` attribute on a task to have Whiskey install a module in this directory or the `GetPowerShellModule` task to install a module in the appropriate place.

    Pass the name of the modules to the `Name` parameter.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'BuildMasterAutomtion'

    Demonstrates how to use this method to import a single module.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'BuildMasterAutomtion','ProGetAutomation'

    Demonstrates how to use this method to import multiple modules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The module names to import.
        [String[]]$Name,

        [Parameter(Mandatory)]
        # The path to the build root, where the PSModules directory can be found.
        [String]$PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    & {
        $VerbosePreference = 'SilentlyContinue'
        Get-Module -Name $Name | Remove-Module -Force -WhatIf:$false
    }

    $relativePSModulesRoot = Resolve-Path -Path $PSModulesRoot -Relative -ErrorAction Ignore

    foreach( $moduleName in $Name )
    {
        $module = $null
        $moduleDir = Join-Path -Path $PSModulesRoot -ChildPath $moduleName

        if(Test-WhiskeyPowerShellModule -Name $moduleName)
        {
            $module = $moduleName
        }
        elseif( Test-Path -Path $moduleDir -PathType Container )
        {
            $module = $moduleDir
        }

        if( $module )
        {
            Write-WhiskeyDebug -Message ('PSModuleAutoLoadingPreference = "{0}"' -f $PSModuleAutoLoadingPreference)
            Write-WhiskeyVerbose -Message ('Importing PowerShell module "{0}" from "{1}".' -f $moduleName,$relativePSModulesRoot)
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
            continue
        }

        if( -not (Get-Module -Name $moduleName) )
        {
            Write-WhiskeyError -Message ('Module "{0}" does not exist. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.' -f $moduleName) -ErrorAction Stop
        }
    }
}
