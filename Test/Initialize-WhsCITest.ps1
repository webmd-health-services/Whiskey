
foreach( $arcModule in @( 'WhsAutomation', 'WhsSettings' ) )
{
    Remove-Module -Name $arcModule -Force -ErrorAction Ignore
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\Carbon' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\powershell-yaml')
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\BuildMasterAutomation\Import-BuildMasterAutomation.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCITest.psm1') -Force
