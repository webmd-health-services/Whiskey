
function Import-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Imports a PowerShell module.

    .DESCRIPTION
    The `Import-WhiskeyPowerShellModule` function imports a PowerShell module that is needed/used by a Whiskey task.
    Since Whiskey tasks all run in the module's scope, the imported modules are imported into the global scope. If the
    module is currently loaded but is at a different version than requested, that module is removed first, and the 
    correct version is imported.

    If the module isn't installed (or if the requested version of the module isn't installed), you'll get an error. Use
    the `Install-WhiskeyPowerShellModule` to install the module. If a task needs a module, use the 
    `[Whiskey.RequiresPowerShellModule]` task attribute.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -PSModulesRoot $buildRoot

    Demonstrates how to use this method to import a module that is installed in a global module location or in the 
    current build's PSModules directory (usually in the build root directory). The latest/newest installed version is
    imported.

    .EXAMPLE
    Import-WhiskeyPowerShellModule -Name 'Zip' -Version '0.2.0' -PSModulesRoot $buildRoot

    Demonstrates how to use this method to import a specific version of a module that is installed in a global module 
    location or in the current build's PSModules directory (usually in the build root directory). The latest/newest
    installed version is imported.
    #>
    [CmdletBinding()]
    param(
        # The module names to import.
        [Parameter(Mandatory, ParameterSetName='RequiredVersion')]
        [Parameter(Mandatory, ParameterSetName='MinMax')]
        [String]$Name,

        # The minimum version of the module to import.
        [Parameter(ParameterSetName='MinMax')]
        [String] $MinVersion,

        # The maximum version of the module to import.
        [Parameter(ParameterSetName='MinMax')]
        [String] $MaxVersion,

        # The required version of the module to import.
        [Parameter(ParameterSetName='RequiredVersion')]
        [String] $RequiredVersion,

        # The path to the build root, where the PSModules directory can be found. Must be included to import a locally installed module.
        [Parameter(Mandatory, ParameterSetName='RequiredVersion')]
        [Parameter(Mandatory, ParameterSetName='MinMax')]
        $PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $numErrorsBefore = $Global:Error.Count
    $foundModule = $false
    try
    {
        $foundModule = & {
            $VerbosePreference = 'SilentlyContinue'
            $module = Get-WhiskeyPSModule -Name $Name -RequiredVersion $RequiredVersion -PSModulesRoot $PSModulesRoot

            if( $MinVersion -and $MaxVersion )
            {
                $module = Get-WhiskeyPSModule -Name $Name -MinVersion $MinVersion -MaxVersion $MaxVersion -PSModulesRoot $PSModulesRoot
            }

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

            $DebugPreference = 'Continue'
            Write-Debug -Message "Importing $($module.Name) version $($module.Version)"
            $module | Import-Module -Global -ErrorAction Stop -Verbose:$false -WarningAction 'Ignore' -Force
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
