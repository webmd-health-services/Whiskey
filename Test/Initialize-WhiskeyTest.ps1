
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\BuildMasterAutomation\Import-BuildMasterAutomation.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\ProGetAutomation\Import-ProGetAutomation.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Modules\Carbon' -Resolve) -Force

foreach( $name in @( 'PackageManagement', 'PowerShellGet' ) )
{
    if( (Get-Module -Name $name) )
    {
        Remove-Module -Name $name -Force
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath ('..\Whiskey\{0}' -f $name) -Resolve) -Force
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force


