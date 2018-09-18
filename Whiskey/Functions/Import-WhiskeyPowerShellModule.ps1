
function Import-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Imports a PowerShell module.

    .DESCRIPTION
    The `Import-WhiskeyPowerShellModule` function imports a module into the global scope. The module must be installed in Whiskey's PowerShell modules directory. Use the `RequiresTool` attribute on a task to have Whiskey install a module in this directory.

    Pass the name of the module to the `Name` parameter. If any module with that name is already imported, it is removed, and the module in the current build's PowerShell module's directory is imported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]
        $Name
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    Get-Module -Name $Name | Remove-Module -Force -WhatIf:$false

    $searchPaths = & {
                        Join-Path -Path (Get-Location).Provider -ChildPath $powerShellModulesDirectoryName
                        Join-Path -Path $PSScriptRoot -ChildPath '..' -Resolve
                   }

    foreach( $moduleName in $Name )
    {
        foreach( $searchDir in  $searchPaths )
        {
            $moduleDir = Join-Path -Path $searchDir -ChildPath $moduleName
            if( (Test-Path -Path $moduleDir -PathType Container) )
            {
                Write-Debug -Message ('PSModuleAutoLoadingPreference = "{0}"' -f $PSModuleAutoLoadingPreference)
                Import-Module -Name $moduleDir -Global -Force
            }
        }

        if( -not (Get-Module -Name $moduleName) )
        {
            Write-Error -Message ('Module "{0}" does not exist. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.')
        }
    }
}