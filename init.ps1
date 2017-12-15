<#
.SYNOPSIS
Initializes this repository for development.

.DESCRIPTION
The `init.ps1` script initializes this repository for development. It:

 * Installs NuGet packages for Pester
#>
[CmdletBinding()]
param(
    [object]
    $TaskContext,

    [Switch]
    # Removes any previously downloaded packages and re-downloads them.
    $Clean
)

Set-StrictMode -Version 'Latest'
#Requires -Version 4

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '.\Whiskey\bin\NuGet.exe' -Resolve
$packagesPath = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
& $nugetPath install '7-Zip.x64' -OutputDirectory $packagesPath -Version '16.2.1'

$installPath = Join-Path -Path $packagesPath -ChildPath '7-Zip'
if( -not (Test-Path -Path $installPath -PathType Container) )
{
    New-Item -Path $installPath -ItemType 'Directory'
}

robocopy (Join-Path -Path $packagesPath -ChildPath '7-Zip.x64.16.02.1\tools') $installPath /MIR /R:0 /NDL /NP /NJH /NJS
if( $LASTEXITCODE -lt 8 )
{
    exit 0
}
