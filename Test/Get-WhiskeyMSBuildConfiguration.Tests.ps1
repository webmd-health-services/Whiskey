
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Get-WhiskeyMSBuildConfiguration.when not set and run by developer' {
    $context = New-WhiskeyContextObject
    $context.RunBy = [Whiskey.RunBy]::Developer
    It ('should be set to "Debug"') {
        Get-WhiskeyMSBuildConfiguration -Context $context | Should -Be 'Debug'
    }
}
 
Describe 'Get-WhiskeyMSBuildConfiguration.when not set and run by build server' {
    $context = New-WhiskeyContextObject
    $context.RunBy = [Whiskey.RunBy]::BuildServer
    It ('should be set to "Release"') {
        Get-WhiskeyMSBuildConfiguration -Context $context | Should -Be 'Release'
    }
}

Describe 'Get-WhiskeyMSBuildConfiguration.when customized' {
    $context = New-WhiskeyContextObject
    $context.RunBy = [Whiskey.RunBy]::BuildServer
    Set-WhiskeyMSBuildConfiguration -Context $context -Value 'FizzBuzz'
    It ('should be set to custom value') {
        Get-WhiskeyMSBuildConfiguration -Context $context | Should -Be 'FizzBuzz'
    }
}
 