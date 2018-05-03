
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$pesterPath = $null
$version = $null
$taskParameter = @{}
$failed = $false
$output = $null
$describeReportRowCount = 0
$itReportRowCount = 0

function GivenDescribeDurationReportCount
{
    param(
        $Count
    )

    $taskParameter['DescribeDurationReportCount'] = $Count
}

function GivenItDurationReportCount
{
    param(
        $Count
    )

    $taskParameter['ItDurationReportCount'] = $Count
}

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

function Init
{
    $script:taskParameter = @{}
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

function GivenExclude
{
    param(
        $Exclude
    )

    $taskParameter['Exclude'] = $Exclude
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
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester4'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function Get-OutputReportRowCount
{
    param(
        $Regex
    )

    $report = $output | Out-String
    $report = $report -split ([regex]::Escape([Environment]::Newline))
    $reportStarted = $false
    $rowCount = 0
    for( $idx = 0; $idx -lt $report.Count; ++$idx )
    {
        if( $reportStarted )
        {
            if( -not $report[$idx] )
            {
                break
            }
            $rowCount++
            continue
        }

        if( $report[$idx] -match $Regex )
        {
            $idx++
            $reportStarted = $true
        }
    }
    return $rowCount
}

function ThenDescribeDurationReportHasRows
{
    param(
        $Count
    )

    It ('should output {0} rows in the Describe Duration Report' -f $Count) {
        Get-OutputReportRowCount -Regex '\bDescribe\b +\bDuration\b' | Should -Be $Count
    }
}

function ThenItDurationReportHasRows
{
    param(
        $Count
    )

    It ('should output {0} rows in the It Duration Report' -f $Count) {
        Get-OutputReportRowCount -Regex '\bDescribe\b +\bName\b +\bTime\b' | Should -Be $Count
    }
}

function ThenPesterShouldBeInstalled
{
    param(
        [string]
        $ExpectedVersion
    )

    $pesterDirectoryName = 'Modules\Pester'
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = 'Modules\Pester\{0}' -f $ExpectedVersion
    }

    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    $pesterPath = Join-Path -Path $pesterPath -ChildPath 'Pester.psd1'

    It ('should install version {0}' -f $ExpectedVersion) {
        $module = Test-ModuleManifest -Path $pesterPath
        $module.Version.ToString() | Should -BeLike $ExpectedVersion
    }

    It 'should pass' {
        $script:failed | Should Be $false
    }
    It 'Should pass the build root to the Install tool' {
        $pesterPath | Should Exist
    }
}

function ThenPesterShouldBeUninstalled 
{
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

    It 'should attempt to uninstall Pester' {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -Times 1 -ModuleName 'Whiskey'
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
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester+*.xml' |
                        Where-Object { $_.Name -match '^pester\+.{8}\..{3}\.xml$' }
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

function ThenNoPesterTestFileShouldExist 
{
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    it 'should not have created any test reports' {
        $testReports | should BeNullOrEmpty
    }
}

function ThenNoDurationReportPresent
{
    It ('should not output a duration report') {
        $output | Out-String | Should -Not -Match '\bDescribe\b( +\bName\b)? +\b(Duration|Time)\b'
    }
}

function ThenTestShouldCreateMultipleReportFiles
{
    It 'should create multiple report files' {
        Get-ChildItem -Path (Join-Path -Path $context.OutputDirectory -ChildPath 'pester+*.xml') |
            Measure-Object |
            Select-Object -ExpandProperty 'Count' |
            Should -Be 2
    }
}

Describe 'Pester4.when running passing Pester tests' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked 
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 4
    ThenPesterShouldBeInstalled '4.0.3'
    ThenNoDurationReportPresent
}

Describe 'Pester4.when running failing Pester tests' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'FailingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 0
    ThenTestShouldFail -failureMessage 'Pester tests failed'
}

Describe 'Pester4.when running multiple test scripts' {
    Init
    GivenTestContext
    GivenPesterPath 'FailingTests','PassingTests'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 4
}

Describe 'Pester4.when run multiple times in the same build' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'  
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 8 -FailureCount 0
    ThenPesterShouldBeInstalled '4.0.3'
    ThenTestShouldCreateMultipleReportFiles
}

Describe 'Pester4.when missing Path Configuration' {
    Init
    GivenTestContext
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'Element ''Path'' is mandatory.'
}

Describe 'Pester4.when missing Version configuration' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 4 -FailureCount 0
    ThenPesterShouldBeInstalled '4.*'
}

Describe 'Pester4.when Version property isn''t a version' {
    Init
    GivenTestContext
    GivenVersion 'fubar'
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'isn''t a valid version'
}

Describe 'Pester4.when version of tool doesn''t exist' {
    Init
    GivenTestContext
    GivenInvalidVersion
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'does not exist'
}

Describe 'Pester4.when a task path is absolute' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'C:\FubarSnafu'
    GivenVersion '4.0.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'absolute'
}

Describe 'Pester4.when version of tool is less than 4.*' {
    Init
    GivenTestContext
    GivenVersion '3.4.3'
    GivenPesterPath -pesterPath 'PassingTests' 
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'the major version number must always be ''4'''

}
Describe 'Pester4.when running passing Pester tests with Clean Switch' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    GivenWithCleanFlag
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
    ThenPesterShouldBeUninstalled -withClean
}

Describe 'Pester4.when running passing Pester tests with initialization switch' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '4.0.3'
    GivenWithInitilizeFlag
    WhenPesterTaskIsInvoked
    ThenNoPesterTestFileShouldExist
    ThenPesterShouldBeInstalled '4.0.3'
}

Describe 'Pester4.when showing duration reports' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenDescribeDurationReportCount 1
    GivenItDurationReportCount 1
    WhenPesterTaskIsInvoked 
    ThenDescribeDurationReportHasRows 1
    ThenItDurationReportHasRows 1
}

Describe 'Pester4.when excluding tests and an exclusion filter doesn''t match' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests','FailingTests'
    GivenExclude '*fail*','Passing*'
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 4
}

Describe 'Pester4.when excluding tests and exclusion filters match all paths' {
    Init
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests','FailingTests'
    GivenExclude '*\Fail*','*\Passing*'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenNoPesterTestFileShouldExist
    ThenTestShouldFail ([regex]::Escape('Found no tests to run. Property "Exclude" matched all paths in the "Path" property.'))
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
}
