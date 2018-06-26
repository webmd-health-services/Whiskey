
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Set-WhiskeyMSBuildConfiguration' {
    $context = New-WhiskeyContextObject
    Set-WhiskeyMSBuildConfiguration -Context $context -Value 'FubarSnafu'
    It ('should set MSBuild configuration' ) {
        $context.MSBuildConfiguration | Should -Be 'FubarSnafu'
        Get-WhiskeyMSBuildConfiguration -Context $context | Should -Be 'FubarSnafu'
    }
}
