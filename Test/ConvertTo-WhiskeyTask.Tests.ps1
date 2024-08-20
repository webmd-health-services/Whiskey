
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testNum = 0

    function WhenConverting
    {
        param(
            [Parameter(Mandatory, Position=0)]
            [String] $Yaml
        )

        $yamlFilePath = Join-Path -Path $TestDrive -ChildPath "whiskey.${script:testNum}.yml"

        $Yaml | Set-Content -Path $yamlFilePath

        $ctx = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath $yamlFilePath

        $script:task =
            $ctx.Configuration['Build'] |
            ForEach-Object { Invoke-WhiskeyPrivateCommand -Name 'ConvertTo-WhiskeyTask' -Parameter @{ InputObject = $_ } }
    }
}

Describe 'ConvertTo-WhiskeyTask' {
    BeforeEach {
        $script:testNum += 1
    }

    It 'parses tasks' {
        WhenConverting @'
# These are the supported forms of declaring a task in Whiskey.
Build:
- Task1:
     Property1: Value1
     Property2: Value2
- Task2: Value3
  Property4: Value4
- Value5
- Value6 Arg1 Arg 2
'@

        $script:task | Should -HaveCount 8
        $script:task[0] | Should -Be 'Task1'
        $script:task[1]['Property1'] | Should -Be 'Value1'
        $script:task[1]['Property2'] | Should -Be 'Value2'

        $script:task[2] | Should -Be 'Task2'
        $script:task[3]['Task2'] | Should -BeNullOrEmpty
        $script:task[3]['Property4'] | Should -Be 'Value4'

        $script:task[4] | Should -Be 'Value5'
        $script:task[5].Count | Should -Be 0

        $script:task[6] | Should -Be 'Value6 Arg1 Arg 2'
        $script:task[7].Count | Should -Be 0
    }

    It 'always uses first property as name' {
        WhenConverting @'
Build:
- unwieldy: value
  imaginary: value
  guess: value
  surround: value
  unkempt: value
  type: value
  bawdy: value
  grubby: value
  cumbersome: value
  miss: value
  sable: value
  history: value
  base: value
'@

        $script:task[0] | Should -Be 'unwieldy'
        $script:task[1].Count | Should -Be 12

    }
}