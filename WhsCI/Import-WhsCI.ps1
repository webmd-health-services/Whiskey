
& (Join-Path -Path $PSScriptRoot -ChildPath '..\LibGit2\Import-LibGit2.ps1' -Resolve)

if( (Get-Module -Name 'WhsCI') )
{
    Remove-Module -Name 'WhsCI' -Force
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCI.psd1' -Resolve)
