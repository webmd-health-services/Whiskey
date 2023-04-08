
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDir = $null
    $script:context = $null
    $script:version = $null
    $script:failed = $false
    $script:failureMessage = $null
    $script:output = $null
    $script:whiskeyYamlPath = $null

    function GetOutputPath
    {
        $script:outputFileRoot = $script:context.OutputDirectory.Name
        return Join-Path -Path $script:outputFileRoot -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
    }

    function GivenTestFile
    {
        param(
            [String] $Path,

            [String] $Content
        )

        if( -not [IO.Path]::IsPathRooted($Path) )
        {
            $Content | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath $Path)
        }
    }

    function GivenWhiskeyYml
    {
        param(
            $Content
        )

        $script:whiskeyYamlPath = (Join-Path -Path $script:testDir -ChildPath 'whiskey.yml')
        $Content | Set-Content -Path $script:whiskeyYamlPath
    }

    function ThenDidNotFail
    {
        param(
            [Switch] $AndPublishedTestResult
        )

        $script:failed | Should -Be $false

        if( $AndPublishedTestResult )
        {
            Join-Path -Path $script:context.OutputDirectory -ChildPath 'pester*.xml' | Should -Exist
            Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'
        }
        else
        {
            Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey' -Times 0
        }
    }

    function ThenFailed
    {
        param(
            [String] $WithErrorMatching
        )

        $script:failed | Should -BeTrue
        if( $WithErrorMatching )
        {
            $Global:Error | Should -Match $WithErrorMatching
        }
    }

    function WhenPesterTaskIsInvoked
    {
        [CmdletBinding()]
        param(
        )

        $script:failed = $false
        $Global:Error.Clear()

        Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

        $script:context = New-WhiskeyTestContext -ForDeveloper `
                                                -ConfigurationPath $script:whiskeyYamlPath `
                                                -ForBuildRoot $script:testDir `
                                                -IncludePSModule 'Pester'

        $taskParameter =
            $script:context.Configuration['Build'] |
            Where-Object { $_.ContainsKey('Pester') } |
            ForEach-Object { $_['Pester'] }

        try
        {
            $script:output = Invoke-WhiskeyTask -TaskContext $script:context -Parameter $taskParameter -Name 'Pester'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'Pester' {
    BeforeEach {
        $script:version = $null
        $script:failed = $false
        $script:failureMessage = $null
        $script:whiskeyYamlPath = $null
        $Global:Error.Clear()

        $script:testDir = New-WhiskeyTestRoot

        $script:context = New-WhiskeyTestContext -ForTaskName 'Pester' `
                                                -ForDeveloper `
                                                -ForBuildRoot $script:testDir `
                                                -IncludePSModule 'Pester'

        $pesterModuleRoot = Join-Path -Path $script:testDir -ChildPath ('{0}\Pester' -f $TestPSModulesDirectoryName)
        Get-ChildItem -Path $pesterModuleRoot -ErrorAction Ignore |
            Where-Object { $_.Name -notlike '5.*' } |
            Remove-Item -Recurse -Force
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'succeeds when no failing tests' {
        GivenTestFile 'PassingTests.Tests.ps1' @'
Describe 'One' {
    It 'should pass 1' {
        $true | Should -BeTrue
    }
    It 'should pass again 2' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path : 'PassingTests.Tests.ps1'
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail
    }

    It 'fails build when any tests file' {
        GivenTestFile 'FailingTests.Tests.ps1' @'
Describe 'Failing' {
    It 'should fail 1' {
        $true | Should -BeFalse
    }
    It 'should fail 2' {
        $true | Should -BeFalse
    }
}
'@
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path : 'FailingTests.Tests.ps1'
                    Throw: true
"@
        WhenPesterTaskIsInvoked -ErrorVariable failureMessage
        if( $null -ne ($script:failureMessage | Where-Object {$_ -match 'Pester run failed'}) )
        {
            $script:failed = $true
        }
        ThenFailed
    }

    It 'runs multiple test scripts' {
        GivenTestFile 'FailingTests.Tests.ps1' @'
Describe 'Failing' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        GivenTestFile 'PassingTests.Tests.ps1' @'
Describe 'Passing' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path : '*Tests.Tests.ps1'
                    Throw: true
"@
        WhenPesterTaskIsInvoked -ErrorVariable failureMessage
        if( $null -ne ($script:failureMessage | Where-Object {$_ -match 'Pester run failed'}) )
        {
            $script:failed = $true
        }
        ThenFailed
    }

    It 'passes custom arguments to Pester' {
        GivenTestFile 'PassingTests.Tests.ps1' @'
Describe 'PassingTests'{
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @'
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path: 'PassingTests.Tests.ps1'
                TestResult:
                    Enabled: true
                    OutputPath: '.output\pester.xml'
                    OutputFormat: 'JUnitXml'
'@
        WhenPesterTaskIsInvoked
        ThenDidNotFail -AndPublishedTestResult
    }

    It 'passes arguments to test script' {
        $oneValue = [Guid]::NewGuid()
        $twoValue = [Guid]::NewGuid()
        $threeValue = [Guid]::NewGuid()
        $fourValue = [Guid]::NewGuid()
        $testContent = @"
param(
    [Parameter(Mandatory,Position=0)]
    [String]`$One,

    [Parameter(Mandatory,Position=1)]
    [String]`$Two,

    [Parameter(Mandatory)]
    [String]`$Three,

    [Parameter(Mandatory)]
    [String]`$Four
)

Describe 'ArgTest' {
    It 'should pass them' {
        `$One | Should -Be '$($oneValue)'
        `$Two | Should -Be '$($twoValue)'
        `$Three | Should -Be '$($threeValue)'
        `$Four | Should -Be '$($fourValue)'
    }
}
"@
        GivenTestFile 'ArgTest.Tests.ps1' $testContent
        GivenTestFile 'Arg2Test.Tests.ps1' $testContent
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration: {}
            Container:
                Path: 'Arg*.Tests.ps1'
                Data:
                    One: $($oneValue)
                    Two: $($twoValue)
                    Three: $($threeValue)
                    Four: $($fourValue)
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail
    }

    It 'passes list of paths correctly'{
        GivenTestFile 'PassingTests.ps1' @'
Describe 'Failing' {
    It 'should fail' {
        $false | Should -BeFalse
    }
}
'@
        GivenTestFile 'PassingTests2.ps1' @'
Describe 'Passing' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path: ['PassingTests.ps1', 'PassingTests2.ps1']
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail
    }

    It 'passes and converts boolean paramers to Pester'{
        GivenTestFile 'PassingTests.ps1' @'
Describe 'Passing' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Path: 'PassingTests.ps1'
                TestResult:
                    Enabled: true
                    OutputPath: $(GetOutputPath)
                    OutputFormat: 'NUnitXml'
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail -AndPublishedTestResult
    }

    It 'passes parameters to script blocks'{
        $oneValue = [Guid]::NewGuid()

        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                TestResult:
                    Enabled: true
                    OutputPath: $(GetOutputPath)
                    OutputFormat: 'NUnitXml'
            Container:
                ScriptBlock:
                    "param(
                        [Parameter(Mandatory)]
                        [String] `$One
                    )
                    Describe 'Passing' {
                        It 'should pass' -TestCases @{ 'One' = `$One} {
                            `$One | Should -Be '$($oneValue)'
                        }
                    }"
                Data:
                    One: $($oneValue)
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail -AndPublishedTestResult
    }

    It 'runs parameter-less script blocks'{
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                TestResult:
                    Enabled: true
                    OutputPath: $(GetOutputPath)
                    OutputFormat: 'NUnitXml'
            Container:
                ScriptBlock:
                    "Describe 'Passing' {
                        It 'should pass' {
                            `$true | Should -BeTrue
                        }
                    }"
"@
        WhenPesterTaskIsInvoked
        ThenDidNotFail -AndPublishedTestResult
    }

    It 'fails build when background tests fail and exit and throw options are false' {
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Exit: false
                    Throw: false
            Container:
                ScriptBlock:
                    "Describe 'Passing' {
                        It 'should pass' {
                            `$false | Should -BeTrue
                        }
                    }"
"@
        WhenPesterTaskIsInvoked
        ThenFailed -WithErrorMatching 'failed'
    }

    It 'fails build when tests run in background job and options exit is true and throw is true' {
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Exit: true
                    Throw: false
            Container:
                ScriptBlock:
                    "Describe 'Passing' {
                        It 'should pass' {
                            `$false | Should -BeTrue
                        }
                    }"
"@
        WhenPesterTaskIsInvoked
        ThenFailed -WithErrorMatching 'failed'
    }

    It 'fails build when tests run in background job and options exit is false and throw is true' {
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Exit: false
                    Throw: true
            Container:
                ScriptBlock:
                    "Describe 'Passing' {
                        It 'should pass' {
                            `$false | Should -BeTrue
                        }
                    }"
"@
        WhenPesterTaskIsInvoked
        ThenFailed -WithErrorMatching 'failed'
    }

    It 'fails build when run in background job and exit and throw options are true' {
        GivenWhiskeyYml @"
        Build:
        - Pester:
            AsJob: true
            Configuration:
                Run:
                    Exit: true
                    Throw: true
            Container:
                ScriptBlock:
                    "Describe 'Passing' {
                        It 'should pass' {
                            `$false | Should -BeTrue
                        }
                    }"
"@
        WhenPesterTaskIsInvoked
        ThenFailed -WithErrorMatching 'failed'
    }
}
