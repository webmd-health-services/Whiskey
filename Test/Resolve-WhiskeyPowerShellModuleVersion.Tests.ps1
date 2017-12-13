
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

InModuleScope 'Whiskey'  {
    Describe 'Resolve-WhiskeyPowerShellModuleVersion.when using exact version' {
        Mock -CommandName 'Find-Module' -ModuleName 'Whiskey'
        $version = Resolve-WhiskeyPowerShellModuleVersion -ModuleName 'Whiskey' -Version '0.20.2'
        It ('should resolve specific version') {
            $version | Should -Be '0.20.2'
        }
        It ('should not search repositories for all versions') {
            Assert-MockCalled -CommandName 'Find-Module' -ModuleName 'Whiskey' -Times 0
        }
    }

    Describe 'Resolve-WhiskeyPowerShellModuleVersion.when using major and minor build numbers only' {
        $version = Resolve-WhiskeyPowerShellModuleVersion -ModuleName 'Whiskey' -Version '0.20'
        It ('should resolve specific version') {
            $version | Should -Be '0.20.0'
        }
    }

    Describe 'Resolve-WhiskeyPowerShellModuleVersion.when using wildcards' {
        $version = Resolve-WhiskeyPowerShellModuleVersion -ModuleName 'Whiskey' -Version '0.20.*'
        It ('should resolve specific version') {
            $version | Should -Be '0.20.2'
        }
    }
}