
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)

if( (Get-Module -Name 'WhsCI') )
{
    Remove-Module -Name 'WhsCI' -Force
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCI.psd1' -Resolve)
