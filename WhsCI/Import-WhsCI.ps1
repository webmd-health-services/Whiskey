
if( (Get-Module -Name 'WhsCI') )
{
    Remove-Module -Name 'WhsCI' -Force
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCI.psd1' -Resolve)


if( (Get-Module -Name 'ProGetAutomation') )
{
    Remove-Module -Name 'ProGetAutomation' -Force
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '.\ProGetAutomation\ProGetAutomation.psm1' -Resolve)
