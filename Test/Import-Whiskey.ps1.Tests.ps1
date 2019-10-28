
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Import-WhiskeyPs1 when Whiskey is not loaded' {
    It 'should load the module' {
        if( (Get-Module -Name 'Whiskey') )
        {
            Remove-Module -Name 'Whiskey'
        }

        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

        Get-Module -Name 'Whiskey' | Should -Not -BeNullOrEmpty
    }
}

Describe 'Import-WhiskeyPs1 when Whiskey is loaded' {
    It 'should load the module' {

        $Global:Error.Clear()

        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

        Get-Module -Name 'Whiskey' | Should -Not -BeNullOrEmpty

        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

        $Global:Error.Count | Should -Be 0
    }
}

