
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
        [String]$Name,

        # The version of the module to import.
        [String]$Version,

        # The path to the build root, where the PSModules directory can be found.
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
        if(-not $Version)
        {
            $Version = '*'
        }

        $globalModules = Get-Module -Name $Name -ListAvailable -ErrorAction Ignore

        foreach ($globalModule in $globalModules)
        {
            if($globalModule.Version -like $Version)
            {
                $module = $globalModule.Path
                break
            } 
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
                Write-WhiskeyError -Message ('Version "{0}" of module "{1}" does not exist in the global scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.' -f $Version,$Name) -ErrorAction Stop
            }
            else
            {
                Write-WhiskeyError -Message ('Module "{0}" does not exist in the global scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.' -f $Name) -ErrorAction Stop
            }

        }
        else
        {
            Write-WhiskeyError -Message ('Module "{0}" does not exist in the local scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.' -f $Name) -ErrorAction Stop
        }
    }
}
