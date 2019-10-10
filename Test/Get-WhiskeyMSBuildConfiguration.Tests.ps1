
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Get-MSBuildConfiguration
{
    param(
        $Context
    )

    Invoke-WhiskeyPrivateCommand -Name 'Get-WhiskeyMSBuildConfiguration' `
                                 -Parameter @{ 'Context' = $context }
}

function New-Context
{
    Invoke-WhiskeyPrivatecommand -Name 'New-WhiskeyContextObject'
}

Describe 'Get-WhiskeyMSBuildConfiguration.when not set and run by developer' {
    $context = New-Context
    $context.RunBy = [Whiskey.RunBy]::Developer
    It ('should be set to "Debug"') {
        Get-MSBuildConfiguration -Context $context | Should -Be 'Debug'
    }
}
 
Describe 'Get-WhiskeyMSBuildConfiguration.when not set and run by build server' {
    $context = New-Context
    $context.RunBy = [Whiskey.RunBy]::BuildServer
    It ('should be set to "Release"') {
        Get-MSBuildConfiguration -Context $context | Should -Be 'Release'
    }
}

Describe 'Get-WhiskeyMSBuildConfiguration.when customized' {
    $context = New-Context
    $context.RunBy = [Whiskey.RunBy]::BuildServer
    Set-WhiskeyMSBuildConfiguration -Context $context -Value 'FizzBuzz'
    It ('should be set to custom value') {
        Get-MSBuildConfiguration -Context $context | Should -Be 'FizzBuzz'
    }
}
 