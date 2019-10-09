
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$powershellModulesDirectoryName = 'PSModules'

$testRoot = $null
$context = $null
$taskParameter = @{}
$failed = $false

$repoRoot = Join-Path -Path $PSScriptRoot -ChildPath '..' -Resolve
$psmodulesRoot = Join-Path -Path $repoRoot -ChildPath ('{0}' -f $powershellModulesDirectoryName) -Resolve
if( -not (Test-Path -Path (Join-Path -Path $psmodulesRoot -ChildPath 'Pester\3.*')) )
{
    Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyPowerShellModule' -Parameter @{
        'Name' = 'Pester';
        'Version' = '3.*';
        'Path' = $repoRoot;
    }
}

# So we can mock Whiskey's private function.
function Publish-WhiskeyPesterTestResult
{
}

function GivenTestContext
{
    param(
    )

    $script:context = New-WhiskeyPesterTestContext 
}

function New-WhiskeyPesterTestContext 
{
    param(
    )

    $optionalParams = @{}

    $script:context = New-WhiskeyTestContext -ForTaskName 'Pester3' `
                                             -ForBuildRoot $testRoot `
                                             -ForDeveloper

    # Make sure only Pester 3 is included.
    $pesterModuleRoot = Join-Path -Path $testRoot -ChildPath ('{0}\Pester' -f $powershellModulesDirectoryName)
    Get-ChildItem -Path $pesterModuleRoot -ErrorAction Ignore | 
        Where-Object { $_.Name -notlike '3.*' } |
        Remove-Item -Recurse -Force

    return $context
}
function GivenVersion
{
    param(
        [string]$Version
    )

    $taskParameter['Version'] = $Version
}

function GivenTestFile
{
    param(
        [string]$Path,
        [string]$Content
    )

    $taskParameter['Path'] = & {
        if( $taskParameter.ContainsKey('Path') )
        {
            $taskParameter['Path']
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

    $script:failed = $false
    $script:taskParameter = @{}
    $Global:Error.Clear()

    $script:testRoot = New-WhiskeyTestRoot
}

function WhenPesterTaskIsInvoked
{
    [CmdletBinding()]
    param(
        [Switch]
        $WithClean
    )

    $failed = $false
    $Global:Error.Clear()

    Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester3'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenPesterShouldBeInstalled
{
    param(
        [string]
        $ExpectedVersion
    )

    $pesterDirectoryName = '{0}\Pester\{1}' -f $powershellModulesDirectoryName,$ExpectedVersion
    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    $pesterPath = Join-Path -Path $pesterPath -ChildPath 'Pester.psd1'

    $manifest = Test-ModuleManifest -Path $pesterPath

    $manifest.Version.ToString() | Should -BeLike $ExpectedVersion
    $script:failed | Should -BeFalse
    $pesterPath | Should -Exist
}

function ThenPesterShouldHaveRun
{
    param(
        [Parameter(Mandatory=$true)]
        [int]
        $FailureCount,
            
        [Parameter(Mandatory=$true)]
        [int]
        $PassingCount
    )
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester+*.xml' |
                        Where-Object { $_.Name -match '^pester\+.{8}\..{3}\.xml$' }
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
        $thisTotal = [int]($xml.'test-results'.'total')
        $thisFailed = [int]($xml.'test-results'.'failures')
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
        $reportPath = $reportPath.FullName
        Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey' -ParameterFilter { 
            $DebugPreference = 'Continue'
            Write-Debug ('{0}  -eq  {1}' -f $Path,$reportPath) 
            $Path -eq $reportPath 
        }
    }
}
function ThenTestShouldFail
{
    param(
        [string]
        $failureMessage
    )
    $Script:failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $failureMessage} | Should -Not -BeNullOrEmpty
}

function ThenNoPesterTestFileShouldExist 
{
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    $testReports | Should -BeNullOrEmpty

}

function ThenTestShouldCreateMultipleReportFiles
{
    Get-ChildItem -Path (Join-Path -Path $context.OutputDirectory -ChildPath 'pester+*.xml') |
        Measure-Object |
        Select-Object -ExpandProperty 'Count' |
        Should -Be 2
}

if( -not $IsWindows )
{
    Describe 'Pester3.when running on non-Windows platform' {
        It 'should fail' {
            Init
            GivenTestContext
            GivenTestFile 'PassingTests.ps1' @'
'@
            WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
            ThenTestShouldFail -failureMessage 'Windows\ platform'
        }
    }

    return
}

Describe 'Pester3.when running passing Pester tests' {
    It 'should not fail' {
        Init
        GivenTestContext
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should Be $true
    }
    It 'should pass 2' {
        $true | Should Be $true
    }
}
'@
        WhenPesterTaskIsInvoked 
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 2
    }
}

Describe 'Pester3.when running failing Pester tests' {
    It 'should fail' {
        Init
        GivenTestContext
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail 1' {
        $true | Should Be $false
    }
    It 'should fail 2' {
        $true | Should Be $false
    }
}
'@
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 2 -PassingCount 0
        ThenTestShouldFail -failureMessage 'Pester tests failed'
    }
}

Describe 'Pester3.when running multiple test scripts' {
    It 'should run them all' {
        Init
        GivenTestContext
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should Be $true
    }
}
'@
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail' {
        $true | Should Be $false
    }
}
'@
        WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 1 -PassingCount 1
    }
}

Describe 'Pester3.when run multiple times in the same build' {
    It 'should output separate reports for each run' {
        Init
        GivenTestContext
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should Be $true
    }
}
'@
        WhenPesterTaskIsInvoked
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 2 -FailureCount 0
        ThenTestShouldCreateMultipleReportFiles
    }
}

Describe 'Pester3.when missing Path Configuration' {
    It 'should fail' {
        Init
        GivenTestContext
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'Element ''Path'' is mandatory.'
    }
}

Describe 'Pester3.when missing Version configuration' {
    It 'should install latest version of Pester 3' {
        Init
        GivenTestContext 
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should Be $true
    }
}
'@
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 1 -FailureCount 0
        ThenPesterShouldBeInstalled '3.4.6'
    }
}

Describe 'Pester3.when customizing version' {
    It 'should install latest version of Pester 3' {
        Init
        GivenVersion '3.4.5'
        GivenTestContext 
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should Be $true
    }
}
'@
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 1 -FailureCount 0
        ThenPesterShouldBeInstalled '3.4.5'
    }
}

Describe 'Pester3.when a task path is absolute' {
    It 'should fail' {
        Init
        GivenTestContext
        GivenTestFile 'C:\FubarSnafu'
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'absolute'
    }
}
