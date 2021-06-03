
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$validYaml = @"
Build:
- TaskDefaults:
    Pester4:
        Verbose: false

- GetPowerShellModule:
    Name: BuildMasterAutomation
    Version: 0.6.*

- GetPowerShellModule:
    Name: ProGetAutomation
    Version: 0.9.*

- GetPowerShellModule:
    Name: BitbucketServerAutomation
    Version: 0.9.*

- GetPowerShellModule:
    Name: VSSetup
    Version: 2.*

- GetPowerShellModule:
    Name: Zip
    Version: 0.3.*

"@

$brokenYaml = @"
Build:
- TaskDefaults:
    Pester4:
        Verbose: false

- GetPowerShellModule:
    Name: BuildMasterAutomation
    Version: 0.6.*

- GetPowerShellModule:
    Name: ProGetAutomation
    Version: 0.9.*

- GetPowerShellModule:
    Name: BitbucketServerAutomation
    Version: 0.9.*

- GetPower
ShellModule:
    Name: VSSetup
    Version: 2.*

- GetPowerShellModule:
    Name: Zip
    Version: 0.3.*

"@

Describe 'Yaml is properly formatted' {
    It 'should not throw error' {
        { Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $validYaml } } | Should -Not -Throw
    }
}

Describe 'Yaml is not properly formatted' {
    It 'should throw error' {
        { Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $brokenYaml } } | Should -Throw "whiskey.yml cannot be parsed"

    }
}

