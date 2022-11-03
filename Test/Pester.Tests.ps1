Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$version = $null
$failed = $false
$failureMessage = $null
$output = $null
$whiskeyYamlPath = $null

function GetOutputPath
{
    $outputFileRoot = $context.OutputDirectory.Name
    return Join-Path -Path $outputFileRoot -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
}

function GivenTestFile
{
    param(
        [String] $Path,

        [String] $Content
    )

    if( -not [IO.Path]::IsPathRooted($Path) )
    {
        $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $Path)
    }
}

function GivenWhiskeyYml
{
    param(
        $Content
    )

    $script:whiskeyYamlPath = (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')
    $Content | Set-Content -Path $whiskeyYamlPath
}

function Init
{
    $script:version = $null
    $script:failed = $false
    $script:failureMessage = $null
    $script:whiskeyYamlPath = $null
    $Global:Error.Clear()

    $script:testRoot = New-WhiskeyTestRoot

    $script:context = New-WhiskeyTestContext -ForTaskName 'Pester' `
                                             -ForDeveloper `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'Pester'

    $pesterModuleRoot = Join-Path -Path $testRoot -ChildPath ('{0}\Pester' -f $TestPSModulesDirectoryName)
    Get-ChildItem -Path $pesterModuleRoot -ErrorAction Ignore |
        Where-Object { $_.Name -notlike '5.*' } |
        Remove-Item -Recurse -Force
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenDidNotFail
{
    param(
        [Switch] $AndPublishedTestResult
    )

    $script:failed | Should -Be $false

    if( $AndPublishedTestResult )
    {
        Join-Path -Path $context.OutputDirectory -ChildPath 'pester*.xml' | Should -Exist
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

    $failed = $false
    $Global:Error.Clear()

    Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

    $script:context = New-WhiskeyTestContext -ForDeveloper `
                                             -ConfigurationPath $whiskeyYamlPath `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'Pester'

    $taskParameter =
        $context.Configuration['Build'] |
        Where-Object { $_.ContainsKey('Pester') } |
        ForEach-Object { $_['Pester'] }

    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Pester.when running passing Pester tests' {
    AfterEach { Reset }
    It 'should run the tests' {
        Init
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
}

Describe 'Pester.when running failing Pester tests' {
    AfterEach { Reset }
    It 'should fail' {
        Init
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
        if( $null -ne ($failureMessage | Where-Object {$_ -match 'Pester run failed'}) )
        {
            $script:failed = $true
        }
        ThenFailed
    }
}

Describe 'Pester.when running multiple test scripts' {
    AfterEach { Reset }
    It 'should run all the scripts' {
        Init
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
        if( $null -ne ($failureMessage | Where-Object {$_ -match 'Pester run failed'}) )
        {
            $script:failed = $true
        }
        ThenFailed
    }
}

Describe 'Pester.when not running task in job' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenTestFile 'PassingTests.Tests.ps1' @"
Describe 'PassingTests' {
    It 'should run inside Whiskey' {
        Test-Path -Path 'variable:psModulesDirectoryName' | Should -BeTrue
        `$script:psModulesDirectoryName | Should -Be "$($TestPSModulesDirectoryName)"
    }
}
"@
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -MockWith {
            @'
<test-results errors="0" failures="0" />
'@
        }
        GivenWhiskeyYml @'
        Build:
        - Pester:
            Configuration: {}
'@
        WhenPesterTaskIsInvoked
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
            Push-Location $testRoot
            try
            {
                $ArgumentList[0] | Should -Be $testRoot
                $expectedManifestPath = Join-Path -Path '*' -ChildPath (Join-Path -Path '5.*' -ChildPath 'Pester.psd1')
                $ArgumentList[1] | Should -BeLike $expectedManifestPath
                $ArgumentList[2] | Should -BeOfType [hashtable]
                $ArgumentList[2] | Should -BeNullOrEmpty
                $ArgumentList[3] | Should -BeNullOrEmpty
                $dirSep = [IO.Path]::DirectorySeparatorChar
                $ArgumentList[4] | Should -BeLike "*$($dirSep).output$($dirSep)Temp*$($dirSep)exitcode"
                $ArgumentList[5] | Should -BeOfType [hashtable]
                $prefNames = @(
                    'DebugPreference',
                    'ErrorActionPreference',
                    'ProgressPreference',
                    'VerbosePreference',
                    'WarningPreference'
                ) | Sort-Object
                $ArgumentList[5].Keys | Sort-Object | Should -Be $prefNames
                return $true
            }
            finally
            {
                Pop-Location
            }
        }
    }
}

Describe 'Pester.when passing custom arguments' {
    AfterEach { Reset }
    It 'should pass the arguments' {
        Init
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
}

Describe 'Pester.when passing named arguments to script' {
    AfterEach { Reset }
    It 'should pass arguments' {
        Init
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
}

Describe 'Pester.when passing an array list'{
    AfterEach { Reset }
    It 'should get converted correctly'{
        Init
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
}

Describe 'Pester.when passing a string boolean value'{
    AfterEach { Reset }
    It 'should get converted correctly and return test results'{
        Init
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
}

Describe 'Pester.when passing a script block with data'{
    AfterEach{ Reset }
    It 'should pass script block correctly'{
        Init
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
}

Describe 'Pester.when passing a script block with no data'{
    AfterEach{ Reset }
    It 'should pass script block correctly'{
        Init
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
}

Describe 'Pester.when tests fail in background job' {
    AfterEach{ Reset }
    It 'should fail the build' {
        Init
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

}

Describe 'Pester.when tests fail in background job and exit configuration option is true' {
    AfterEach{ Reset }
    It 'should fail the build' {
        Init
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
}

Describe 'Pester.when tests fail in background job and throw configuration option is true' {
    AfterEach{ Reset }
    It 'should fail the build' {
        Init
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
}

Describe 'Pester.when tests fail in background job and exit and throw configurations options are true' {
    AfterEach{ Reset }
    It 'should fail the build' {
        Init
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
