<#
.SYNOPSIS
Initializes this repository for development.

.DESCRIPTION
The `init.ps1` script initializes this repository for development. It:

 * Installs NuGet packages for Pester
#>
[CmdletBinding()]
param(
    [Switch]
    # Removes any previously downloaded packages and re-downloads them.
    $Clean
)

Set-StrictMode -Version 'Latest'
#Requires -Version 4

$modules = @{
                'Carbon' = '2.4.1';
                'Pester' = '3.4.6';
            }

foreach( $moduleName in $modules.Keys )
{
    $moduleRootPath = Join-Path -Path $PSScriptRoot -ChildPath $moduleName
    if( (Test-Path -Path $moduleRootPath -PathType Container) )
    {
        if( $Clean )
        {
            Remove-Item -Path $moduleRootPath -Recurse -Force
        }
        else
        {
            continue
        }
    }

    Save-Module -Name $moduleName -Path $PSScriptRoot -RequiredVersion $modules[$moduleName]
}