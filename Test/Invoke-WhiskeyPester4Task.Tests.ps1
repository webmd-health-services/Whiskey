
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$pesterPath = $null
$version = $null
$taskParameter = @{}
$failed = $false

function GivenTestContext
{
    $script:pesterPath = $null
    $script:version = $null
    $script:failed = $false
    $script:taskParameter = @{}
    $Global:Error.Clear()
    $script:context = New-WhiskeyPesterTestContext

    $pesterDirectoryName = 'Modules\Pester'
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = 'Modules\Pester\{0}' -f $Version
    }
    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    if(Test-Path $pesterPAth)
    {
        Remove-item $pesterPath -Recurse -Force
    }
}

function New-WhiskeyPesterTestContext 
{
    param()
    process
    {
        $outputRoot = Join-Path -Path $TestDrive.FullName -ChildPath '.\.output'
        if( -not (Test-Path -Path $outputRoot -PathType Container) )
        {
            New-Item -Path $outputRoot -ItemType 'Directory' | Out-Null
        }
        $buildRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Pester' -Resolve
        $script:context = New-WhiskeyTestContext -ForTaskName 'Pester4' -ForOutputDirectory $outputRoot -ForBuildRoot $buildRoot -ForDeveloper
        return $context
    }
}
function GivenVersion
{
    param(
        [string]
        $Version
    )
    $Script:taskparameter['version'] = $Version
}
function GivenInvalidVersion
{
    $Script:taskparameter['version'] = '4.0.0'
    Mock -CommandName 'Test-Path' `
        -ModuleName 'Whiskey' `
        -MockWith { return $False }`
        -ParameterFilter { $Path -eq $context.BuildRoot }
}
function GivenPesterPath
{
    param(
        [string[]]
        $pesterPath
    )
    $script:taskParameter['path'] = $pesterPath 
}

function GivenFindModuleFails
{
    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey' -MockWith { return $Null }
    Mock -CommandName 'Where-Object' -ModuleName 'Whiskey' -MockWith { return $Null }
}
function GivenWithCleanFlag
{
    $context.RunMode = 'Clean'
    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -MockWith { return $true }
}
function GivenWithInitilizeFlag
{
    $context.RunMode = 'initialize'
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
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester4'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}
function ThenTestShouldPass
{
    param(
        [switch]
        $WithClean
    )
    if( -not $script:Taskparameter['Version'] )
    {
        $latestPester = ( Find-Module -Name 'Pester' -AllVersions | Where-Object { $_.Version -like '4.*' } ) 
        $latestPester = $latestPester | Sort-Object -Property Version -Descending | Select-Object -First 1
        $version = $latestPester.Version 
        $script:Taskparameter['Version'] = '{0}.{1}.{2}' -f ($Version.major, $Version.minor, $Version.build)
    }
    else
    {
        $script:Taskparameter['Version'] = $script:Taskparameter['Version'] | ConvertTo-WhiskeySemanticVersion
        $script:Taskparameter['Version'] = '{0}.{1}.{2}' -f ($script:Taskparameter['Version'].major, $script:Taskparameter['Version'].minor, $script:Taskparameter['Version'].patch)
    }
    $pesterDirectoryName = 'Modules\Pester'
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = 'Modules\Pester\{0}' -f $Version
    }
    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    It 'should pass' {
        $script:failed | Should Be $false
    }
    if( -not $WithClean )
    {
        It 'Should pass the build root to the Install tool' {
            $pesterPath | Should Exist
        }
    }
    else
    {
        It 'should attempt to uninstall Pester' {
            Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -Times 1 -ModuleName 'Whiskey'
        }
    }
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
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    #check to see if we were supposed to run any tests.
    if( ($FailureCount + $PassingCount) -gt 0 )
    {
        It 'should run pester tests' {
            $testReports | Should Not BeNullOrEmpty
        }
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
    It ('should run {0} tests' -f $expectedTotal) {
        $total | Should Be $expectedTotal
    }

    It ('should have {0} failed tests' -f $FailureCount) {
        $failed | Should Be $FailureCount
    }

    It ('should run {0} passing tests' -f $PassingCount) {
        $passed | Should Be $PassingCount
    }

    foreach( $reportPath in $testReports )
    {
        It ('should publish {0} test results' -f $reportPath) {
            $reportPath = Join-Path -Path $ReportsIn -ChildPath $reportPath
            Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey' -ParameterFilter { Write-Debug ('{0}  -eq  {1}' -f $Path,$reportPath) ; $Path -eq $reportPath }
        }
    }
}
function ThenTestShouldFail
{
    param(
        [string]
        $failureMessage
    )
    It 'should throw a terminating exception' {
        $Script:failed | Should Be $true
    }
    It 'should fail' {
        $Global:Error | Where-Object { $_ -match $failureMessage} | Should -Not -BeNullOrEmpty
    }
}

function ThenNoPesterTestFileShouldExist {
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    it 'should not have created any test reports' {
        $testReports | should BeNullOrEmpty
    }

}

function ThenTestShouldCreateMultipleReportFiles
{
    It 'should create multiple report files' {
        Join-Path -Path $context.OutputDirectory -ChildPath 'pester-00.xml' | Should Exist
        Join-Path -Path $context.OutputDirectory -ChildPath 'pester-01.xml' | Should Exist
    }
}
function ThenFindModuleShouldHaveBeenCalled
{
    Assert-MockCalled -CommandName 'Find-Module' -Times 1 -ModuleName 'Whiskey'
    Assert-MockCalled -CommandName 'Where-Object' -Times 1 -ModuleName 'Whiskey'
}

Describe 'Invoke-WhiskeyPester4Task.when running passing Pester tests' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked 
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 4
    ThenTestShouldPass
}

Describe 'Invoke-WhiskeyPester4Task.when running failing Pester tests' {
    GivenTestContext
    GivenPesterPath -pesterPath 'FailingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 0
    ThenTestShouldFail -failureMessage 'Pester tests failed'
}

Describe 'Invoke-WhiskeyPester4Task.when running multiple test scripts' {
    GivenTestContext
    GivenPesterPath 'FailingTests','PassingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 4
}

Describe 'Invoke-WhiskeyPester4Task.when run multiple times in the same build' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'  
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 8 -FailureCount 0
    ThenTestShouldPass
    ThenTestShouldCreateMultipleReportFiles
}

Describe 'Invoke-WhiskeyPester4Task.when missing Path Configuration' {
    GivenTestContext
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'Element ''Path'' is mandatory.'
}

Describe 'Invoke-WhiskeyPester4Task.when missing Version configuration' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 4 -FailureCount 0
    ThenTestShouldPass
}

Describe 'Invoke-WhiskeyPester4Task.when Version property isn''t a version' {
    GivenTestContext
    GivenVersion 'fubar'
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'isn''t a valid version'
}

Describe 'Invoke-WhiskeyPester4Task.when version of tool doesn''t exist' {
    GivenTestContext
    GivenInvalidVersion
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'does not exist'
}

Describe 'Invoke-WhiskeyPester4Task.when a task path is absolute' {
    GivenTestContext
    GivenPesterPath -pesterPath 'C:\FubarSnafu'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'absolute'
}

Describe 'Invoke-WhiskeyPester4Task.when Find-Module fails' {
    GivenTestContext
    GivenFindModuleFails
    GivenPesterPath -pesterPath 'PassingTests'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
    ThenFindModuleShouldHaveBeenCalled
    ThenTestShouldFail -failureMessage 'Unable to find a version of Pester 4 to install.'
}

Describe 'Invoke-WhiskeyPester4Task.when version of tool is less than 4.*' {
    GivenTestContext
    GivenVersion '3.4.3'
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'the major version number must always be ''4'''

}
Describe 'Invoke-WhiskeyPester4Task.when running passing Pester tests with Clean Switch' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    GivenWithCleanFlag
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
    ThenTestShouldPass -withClean
}

Describe 'Invoke-WhiskeyPester4Task.when running passing Pester tests with initialization switch' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    GivenWithInitilizeFlag
    WhenPesterTaskIsInvoked
    ThenNoPesterTestFileShouldExist
    ThenTestShouldPass
}
