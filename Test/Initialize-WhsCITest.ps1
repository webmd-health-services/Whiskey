
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCITest.psm1')
