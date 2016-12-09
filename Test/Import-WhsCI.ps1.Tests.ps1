
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

Describe 'Import-WhsCIPs1 when WhsCI is not loaded' {
    if( (Get-Module -Name 'WhsCI') )
    {
        Remove-Module -Name 'WhsCI'
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1')

    It 'should load the module' {
        Get-Module -Name 'WhsCI' | Should Not BeNullOrEmpty
    }
}

Describe 'Import-WhsCIPs1 when WhsCI is loaded' {

    $Global:Error.Clear()

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1')

    It 'should load the module' {
        Get-Module -Name 'WhsCI' | Should Not BeNullOrEmpty
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1')

    It 'should not write an error' {
        $Global:Error.Count | Should Be 0
    }
}
