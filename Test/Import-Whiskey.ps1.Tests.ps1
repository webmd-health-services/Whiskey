
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Import-WhiskeyPs1 when Whiskey is not loaded' {
    if( (Get-Module -Name 'Whiskey') )
    {
        Remove-Module -Name 'Whiskey'
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

    It 'should load the module' {
        Get-Module -Name 'Whiskey' | Should Not BeNullOrEmpty
    }
}

Describe 'Import-WhiskeyPs1 when Whiskey is loaded' {

    $Global:Error.Clear()

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

    It 'should load the module' {
        Get-Module -Name 'Whiskey' | Should Not BeNullOrEmpty
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1')

    It 'should not write an error' {
        $Global:Error.Count | Should Be 0
    }
}

