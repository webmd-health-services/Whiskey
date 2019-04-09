
# Some tests load ProGetAutomation from a Pester test drive. Forcibly remove the module if it is loaded to avoid errors.
if( (Get-Module -Name 'ProGetAutomation') )
{
    Remove-Module -Name 'ProGetAutomation' -Force
}

& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\BuildMasterAutomation' -Resolve) -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\ProGetAutomation' -Resolve) -Force

foreach( $name in @( 'PackageManagement', 'PowerShellGet' ) )
{
    if( (Get-Module -Name $name) )
    {
        Remove-Module -Name $name -Force
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath ('..\Whiskey\Modules\{0}' -f $name) -Resolve) -Force
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force


