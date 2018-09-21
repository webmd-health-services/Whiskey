
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\BuildMasterAutomation' -Resolve) -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\ProGetAutomation' -Resolve) -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Carbon' -Resolve) -Force

foreach( $name in @( 'PackageManagement', 'PowerShellGet' ) )
{
    if( (Get-Module -Name $name) )
    {
        Remove-Module -Name $name -Force
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath ('..\Whiskey\{0}' -f $name) -Resolve) -Force
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force


