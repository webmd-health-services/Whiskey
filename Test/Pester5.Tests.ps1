Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$version = $null
$taskParameter = @{}
$testScript = @{}
$failed = $false
$output = $null

function GivenTestFile
{
    param(
        [String] $Path,

        [String] $Content
    )

    $testScript['Script'] = & {
        if( $testScript.ContainsKey('Script') )
        {
            $testScript['Script']
        }
        $Path 
    }

    if( -not [IO.Path]::IsPathRooted($Path) )
    {
        $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $Path)
    }
}

function Init
{
    $script:taskParameter = @{}
    $script:testScript = @{}
    $script:version = $null
    $script:failed = $false
    $Global:Error.Clear()

    $script:testRoot = New-WhiskeyTestRoot

    $script:context = New-WhiskeyTestContext -ForTaskName 'Pester5' `
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

function ThenNoPesterTestFileShouldExist 
{
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    $testReports | Should -BeNullOrEmpty
}

function ThenPesterShouldHaveRun
{
    param(
        [Parameter(Mandatory)]
        [int] $FailureCount,
            
        [Parameter(Mandatory)]
        [int] $PassingCount,

        [Switch] $AsJUnitXml,

        [String] $ResultFileName = 'pester+*.xml'
    )

    $reportsIn =  $context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter $ResultFileName

    #check to see if we were supposed to run any tests.
    if( ($FailureCount + $PassingCount) -gt 0 )
    {
        $testReports | Should -Not -BeNullOrEmpty
    }

    $total = 0
    $failed = 0
    $passed = 0
    foreach( $testReport in $testReports )
    {
        $xml = [xml](Get-Content -Path $testReport.FullName -Raw)
        $totalAttrName = 'total'
        $disabled = 0
        if( $AsJUnitXml )
        {
            $totalAttrName = 'tests'
            $disabled = [int]($xml.DocumentElement.'disabled')
        }
        $thisTotal = [int]($xml.DocumentElement.$totalAttrName) - $disabled
        $thisFailed = [int]($xml.DocumentElement.'failures')
        $thisPassed = ($thisTotal - $thisFailed)
        $total += $thisTotal
        $failed += $thisFailed
        $passed += $thisPassed
    }

    $expectedTotal = $FailureCount + $PassingCount
    $total | Should -Be $expectedTotal
    $failed | Should -Be $FailureCount
    $passed | Should -Be $PassingCount

    foreach( $reportPath in $testReports )
    {
        Write-WhiskeyDebug -Context $context ('ReportsIn:  {0}' -f $ReportsIn)
        Write-WhiskeyDebug -Context $context ('reportPath: {0}' -f $reportPath)
        $reportPath = Join-Path -Path $ReportsIn -ChildPath $reportPath.Name
        Write-WhiskeyDebug -Context $context ('reportPath: {0}' -f $reportPath)
        Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' `
                          -ModuleName 'Whiskey' `
                          -ParameterFilter { 
                                if( -not [IO.Path]::IsPathRooted($Path) )
                                {
                                    $Path = Join-Path -Path $testRoot -ChildPath $Path
                                }
                                Write-WhiskeyDebug ('{0}  -eq  {1}' -f $Path,$reportPath) 
                                $result = $Path -eq $reportPath 
                                Write-WhiskeyDebug ('  {0}' -f $result) 
                                return $result
                          }
    }
}

function ThenTestShouldCreateMultipleReportFiles
{
    Get-ChildItem -Path (Join-Path -Path $context.OutputDirectory -ChildPath 'pester+*.xml') |
        Measure-Object |
        Select-Object -ExpandProperty 'Count' |
        Should -Be 2
}

function ThenTestShouldFail
{
    param(
        [String] $failureMessage
    )

    $Script:failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $failureMessage} | Should -Not -BeNullOrEmpty
}

function WhenPesterTaskIsInvoked
{
    [CmdletBinding()]
    param(
        [switch] $WithClean,

        [switch] $AsJob,

        [hashtable] $WithArgument = @{ }
    )

    $failed = $false
    $Global:Error.Clear()
    $passThru = $true
    $outputFormat = 'NUnitXml'
    $testName = ''
    $data = $null
    $path = $null
    $exclude = $null

    Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

    if( $AsJob )
    {
        $taskParameter['AsJob'] = 'true'
    }

    if( $WithArgument.ContainsKey('PassThru') ){
        $passThru = $WithArgument.PassThru
    }

    if( $WithArgument.ContainsKey('Output') )
    {
        $outputPath = $WithArgument['Output']
    }
    else
    {
        $outputFileRoot = $context.OutputDirectory.Name
        $outputPath = Join-Path -Path $outputFileRoot -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
    }

    if( $WithArgument.ContainsKey('OutputFormat') )
    {
        $outputFormat = $WithArgument['OutputFormat']
    }

    if($WithArgument.ContainsKey('TestName'))
    {
        $testName = $WithArgument.TestName
    }

    # Checking to see if data is being passed in for tests
    if( $WithArgument.ContainsKey('Script') )
    {
        $path = $WithArgument.Script
        if( $WithArgument.Script.ContainsKey('Data') )
        {
            $data = $WithArgument.Script.Data
        }
    }

    if( $testScript.ContainsKey('Script') )
    {
        $path = $testScript.Script
    }

    if( $WithArgument.ContainsKey('Exclude') )
    {
        $exclude = $WithArgument.Exclude
    }

    # New Pester5 Configuration
    $configuration = @{
        Debug = @{
            ShowFullErrors = ($DebugPreference -eq 'Continue');
            WriteDebugMessages = ($DebugPreference -eq 'Continue');
        };
        Run = @{
            ExcludePath = $exclude;
            Container = @{
                Path = $path;
                Data = $data;
            }
            PassThru = $passThru;
        };
        Filter = @{
            FullName = $testName;
        };
        Should = @{
            ErrorAction = $ErrorActionPreference;
        };
        TestResult = @{
            Enabled = $true;
            OutputPath = $outputPath;
            OutputFormat = $outputFormat;
        };
    }

    $taskParameter['PesterConfiguration'] = $configuration

    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester5'
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
        WhenPesterTaskIsInvoked -AsJob
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 2
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
        WhenPesterTaskIsInvoked -AsJob -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 2 -PassingCount 0
        ThenTestShouldFail -failureMessage 'Pester tests failed'
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
        WhenPesterTaskIsInvoked -AsJob -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 1 -PassingCount 1
    }
}

Describe 'Pester5.when run multiple times in the same build' {
    AfterEach { Reset }
    It 'should run multiple times' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob
        WhenPesterTaskIsInvoked -AsJob
        ThenPesterShouldHaveRun -PassingCount 2 -FailureCount 0
        ThenTestShouldCreateMultipleReportFiles
    }
}

Describe 'Pester5.when missing path' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPesterTaskIsInvoked -AsJob -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'Property "Script": Script is mandatory.'
    }
}

Describe 'Pester5.when a task path is absolute' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $pesterPath = Join-Path -Path $testRoot -ChildPath '..\SomeFile'
        New-Item -Path $pesterPath
        GivenTestFile $pesterPath
        WhenPesterTaskIsInvoked -AsJob -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'outside\ the\ build\ root'
    }
}

Describe 'Pester5.when excluding tests and an exclusion filter doesn''t match' {
    AfterEach { Reset }
    It 'should still run' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' { 
        $true | Should -BeTrue
    }
}
'@
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            'Exclude' = '*fail*','Passing*'
        }
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 1
    }
}

Describe 'Pester5.when excluding tests and exclusion filters match all paths' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            'Exclude' = (Join-Path -Path '*' -ChildPath 'Fail*'),(Join-Path -Path '*' -ChildPath 'Passing*')
        } -ErrorAction SilentlyContinue
        ThenNoPesterTestFileShouldExist
        ThenTestShouldFail ([regex]::Escape('Found no tests to run.'))
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
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
'@ | Set-Content -Path $PesterConfiguration.TestResult.OutputPath
            return ([pscustomobject]@{ 'TestResult' = [pscustomobject]@{ 'Time' = [TimeSpan]::Zero } })
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
                $ArgumentList[2].Run.Container.Path | Should -Be (Join-Path -Path '.' -ChildPath 'PassingTests.ps1')
                $ArgumentList[2].Run.Container.Data | Should -BeNullOrEmpty
                $ArgumentList[2].Filter.FullName | Should -BeNullOrEmpty
                $ArgumentList[2].TestResult.OutputPath | Should -BeLike (Join-Path -Path '.output' -ChildPath 'pester+*.xml')
                $ArgumentList[2].TestResult.OutputFormat | Should -Be 'NUnitXml'
                $ArgumentList[3] | Should -BeOfType [hashtable]
                $prefNames = @(
                    'DebugPreference',
                    'ErrorActionPreference',
                    'ProgressPreference',
                    'VerbosePreference',
                    'WarningPreference'
                ) | Sort-Object
                $ArgumentList[3].Keys | Sort-Object | Should -Be $prefNames
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
            # Make sure the Pester5 task's default values for these get overwritten
            'Output' = '.output\pester.xml';
            'OutputFormat' = 'JUnitXml';
            # Make sure these do *not* get overwritten.
            'PassThru' = $false;
            # Make sure this gets passed.
            'TestName' = 'PassingTests';
        }
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 1 -AsJUnitXml -ResultFileName 'pester.xml'
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
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            'Script' = @{
                'Path' = 'Arg*.ps1';
                'Data' = @{
                    One = $oneValue;
                    Two = $twoValue;
                    Three = $threeValue;
                    Four = $fourValue;
                };
            }
        }
        ThenPesterShouldHaveRun -PassingCount 2 -FailureCount 0
    }
}

Describe 'Pester5.when passing hashtable to script property with multiple paths' {
    AfterEach { Reset }
    It 'should pass arguments' {
        Init
        WhenPesterTaskIsInvoked -AsJob -WithArgument @{
            'Script' = @{
                'Path' = ('Path1.ps1','Path2.ps1');
            };
        } -ErrorAction SilentlyContinue
        ThenTestShouldFail '"Path" value must be a single string'
    }
}