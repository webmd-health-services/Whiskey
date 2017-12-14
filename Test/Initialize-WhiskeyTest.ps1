
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\BuildMasterAutomation\Import-BuildMasterAutomation.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\ProGetAutomation\Import-ProGetAutomation.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force


