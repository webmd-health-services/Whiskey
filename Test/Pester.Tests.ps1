Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$version = $null
$taskParameter = @{}
$failed = $false
$failureMessage = $null
$output = $null

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

    $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')
}

function Init
{
    $script:taskParameter = @{}
    $script:version = $null
    $script:failed = $false
    $script:failureMessage = $null
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
        [switch] $AsJob,

        [switch] $WithYaml,

        [hashtable] $WithArgument = @{ }
    )

    $failed = $false
    $Global:Error.Clear()

    Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

    if( $AsJob )
    {
        $taskParameter['AsJob'] = 'true'
    }

    if( $WithYaml )
    {
        [Whiskey.Context]$yamlContext = New-WhiskeyTestContext -ForDeveloper `
                                                -ForBuildRoot $testRoot `
                                                -ConfigurationPath (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')

        $taskParameter += 
        $yamlContext.Configuration['Build'] | 
        Where-Object { $_.ContainsKey('Pester') } | 
        ForEach-Object { $_['Pester'] }
    }

    if( -not $taskParameter.ContainsKey('Configuration') )
    {
        $taskParameter['Configuration'] = $WithArgument
    }

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

Describe 'Pester5.when running passing Pester tests' {
    AfterEach { Reset }
    It 'should run the tests' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'One' {
    It 'should pass 1' {
        $true | Should -BeTrue
    }
    It 'should pass again 2' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = 'PassingTests.ps1';
            };
        }
        ThenDidNotFail
    }
}

Describe 'Pester5.when running failing Pester tests' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenTestFile 'FailingTests.ps1' @'
Describe 'Failing' {
    It 'should fail 1' {
        $true | Should -BeFalse
    }
    It 'should fail 2' {
        $true | Should -BeFalse
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = 'FailingTests.ps1';
                Throw = $true;
            };
        } -ErrorVariable failureMessage

        if( $null -ne ($failureMessage | Where-Object {$_ -match 'Pester run failed'}) )
        {
            $script:failed = $true
        }
        ThenFailed
    }
}

Describe 'Pester5.when running multiple test scripts' {
    AfterEach { Reset }
    It 'should run all the scripts' {
        Init
        GivenTestFile 'FailingTests.ps1' @'
Describe 'Failing' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        GivenTestFile 'PassingTests.ps1' @'
Describe 'Passing' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = @('FailingTests.ps1', 'PassingTests.ps1');
            };
        } -ErrorAction SilentlyContinue
        ThenDidNotFail
    }
}

Describe 'Pester5.when not running task in job' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenTestFile 'PassingTests.ps1' @"
Describe 'PassingTests' {
    It 'should run inside Whiskey' {
        Test-Path -Path 'variable:powershellModulesDirectoryName' | Should -BeTrue
        `$powerShellModulesDirectoryName | Should -Be "$($TestPSModulesDirectoryName)"
    }
}
"@
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -MockWith {
            @'
<test-results errors="0" failures="0" />
'@ 
        }
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
                $ArgumentList[4] | Should -BeOfType [hashtable]
                $prefNames = @(
                    'DebugPreference',
                    'ErrorActionPreference',
                    'ProgressPreference',
                    'VerbosePreference',
                    'WarningPreference'
                ) | Sort-Object
                $ArgumentList[4].Keys | Sort-Object | Should -Be $prefNames
                return $true
            }
            finally
            {
                Pop-Location
            }
        }
    }
}

Describe 'Pester5.when passing custom arguments' {
    AfterEach { Reset }
    It 'should pass the arguments' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests'{
    It 'should pass' {
        $true | Should -BeTrue
    }
}
Describe 'FailingTests'{
    It 'should fail' {
        $false | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = 'PassingTests.ps1';
            };
            TestResult = @{
                Enabled = $true;
                OutputPath = '.output\pester.xml';
                OutputFormat = 'JUnitXml';
            };
        }
        ThenDidNotFail -AndPublishedTestResult
    }
}

Describe 'Pester5.when passing named arguments to script' {
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
        GivenTestFile 'ArgTest.ps1' $testContent
        GivenTestFile 'Arg2Test.ps1' $testContent
        $taskParameter['Container'] = @{
            Path = ('ArgTest.ps1', 'Arg2Test.ps1');
            Data = @{
                One = $oneValue;
                Two = $twoValue;
                Three = $threeValue;
                Four = $fourValue;
            }
        }
        WhenPesterTaskIsInvoked -AsJob
        ThenDidNotFail
    }
}

Describe 'Pester5.when passing an array list'{
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

        $pathArrayList = [System.Collections.ArrayList]::new()
        $pathArrayList.Add('PassingTests.ps1')
        $pathArrayList.Add('PassingTests2.ps1')

        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = $pathArrayList;
            };
        }
        ThenDidNotFail

    }
}

Describe 'Pester5.when passing a string boolean value'{
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
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            Run = @{
                Path = 'PassingTests.ps1';
            };
            TestResult = @{
                Enabled = 'True';
                OutputPath = GetOutputPath;
                OutputFormat = 'NUnitXml';
            };
        }
        ThenDidNotFail -AndPublishedTestResult
    }
}

Describe 'Pester5.when passing a script block'{
    AfterEach{ Reset }
    It 'should pass script block correctly'{
        Init
        $oneValue = [Guid]::NewGuid()
        $scriptBlock = {
            param(
                [Parameter(Mandatory)]
                [String] $One
            )
            Describe 'Passing' {
                It 'should pass' {
                    $One | Should -Be $oneValue
                }
            }
        }
        $taskParameter['Container'] = @{
            ScriptBlock =  $scriptBlock;
            Data = @{
                One = $oneValue
            }
        }
        WhenPesterTaskIsInvoked -AsJob
        ThenDidNotFail
    }
}

Describe 'Pester5.when passing a script block with no data'{
    AfterEach{ Reset }
    It 'should pass script block correctly'{
        Init
        $scriptBlock = {
            Describe 'Passing' {
                It 'should pass' {
                    $true | Should -BeTrue
                }
            }
        }
        $taskParameter['Container'] = @{
            ScriptBlock =  $scriptBlock;
        }
        WhenPesterTaskIsInvoked -AsJob
        ThenDidNotFail
    }
}

Describe 'Pester5.when configuration is passed in YAML' {
    AfterEach { Reset }
    It 'should pass the configuration correctly' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'One' {
    It 'should pass 1' {
        $true | Should -BeTrue
    }
    It 'should pass again 2' {
        $true | Should -BeTrue
    }
}
'@
        GivenWhiskeyYml @'
        Build:
        - Pester:
            Configuration: 
                Run:
                    Path : 'PassingTests.ps1'
'@

        WhenPesterTaskIsInvoked -AsJob -WithYaml
        ThenDidNotFail
    }
}

Describe 'Pester5.when container is passed in YAML'{
    AfterEach{ Reset }
    It 'should pass container correctly' {
        Init
        $oneValue = [Guid]::NewGuid()
        $testContent = @"
param(
    [Parameter(Mandatory)]
    [String]`$One
)

Describe 'ArgTest' {
    It 'should pass them' {
        `$One | Should -Be '$($oneValue)'
    }
}
"@
        GivenTestFile 'ArgTest.ps1' $testContent
        GivenWhiskeyYml @"
        Build:
        - Pester:
            Container: 
                Path: 'ArgTest.ps1'
                Data: 
                    One: '$($oneValue)'
"@
        WhenPesterTaskIsInvoked -AsJob -WithYaml
        ThenDidNotFail
    }
}