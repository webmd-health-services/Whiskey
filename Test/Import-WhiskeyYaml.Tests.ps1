
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$validYaml = @"
Build:
- GetPowerShellModule:
    Name: VSSetup
    Version: 2.*

"@

$brokenYaml = @"
Build:
- GetPower
ShellMo
dule:
    Name: VSSetup
    Version: 2.*

"@

Describe 'Yaml is properly formatted' {
    It 'should not throw error' {
        { Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $validYaml } } | Should -Not -Throw
    }
}

Describe 'Yaml is not properly formatted' {
    It 'should throw error' {
        { Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $brokenYaml } } | Should -Throw "YAML cannot be parsed:"
    }
}

Describe 'Yaml is not properly formatted in a file' {
    It 'should throw error' {
        $Path = '.\whiskey.sample.yml'
        Mock -CommandName 'Get-Content' -ModuleName 'Whiskey' { return "Build: - GetPowerShellModule:Name: VSSetupVersion: 2.*"}
        { Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Path' = $Path } } | Should -Throw "Whiskey configuration file ""$($Path)"" cannot be parsed"
        Assert-MockCalled -CommandName 'Get-Content' -ModuleName 'Whiskey' -Times 1 -Exactly
    }
}

