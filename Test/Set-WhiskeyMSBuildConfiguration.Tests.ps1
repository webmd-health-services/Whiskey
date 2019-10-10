
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Set-WhiskeyMSBuildConfiguration' {
    $context = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyContextObject'
    Set-WhiskeyMSBuildConfiguration -Context $context -Value 'FubarSnafu'
    It ('should set MSBuild configuration' ) {
        $context.MSBuildConfiguration | Should -Be 'FubarSnafu'
        Invoke-WhiskeyPrivateCommand -Name 'Get-WhiskeyMSBuildConfiguration' `
                                     -Parameter @{ 'Context' = $context } | 
            Should -Be 'FubarSnafu'
    }
}
