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

$modules = @( 'Pester' )

foreach( $moduleName in $modules )
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

    Save-Module -Name $moduleName -Path $PSScriptRoot
}
