
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\BuildMasterAutomation\Import-BuildMasterAutomation.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhsCITest.psm1') -Force
