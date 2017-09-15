Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$buildRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies'

# Build the assemblies that are used for these NUnit tests
$taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $buildRoot -ForOutputDirectory (Join-Path -Path $env:TEMP -ChildPath '.output')
$taskParameter = @{ 'Path' = @('NUnit3PassingTest\NUnit3PassingTest.sln','NUnit3FailingTest\NUnit3FailingTest.sln') }
Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'MSBuild'

$argument = $null
$clean = $false
$coverageFilter = $null
$disableCodeCoverage = $false
$failed = $false
$framework = $null
$initialize = $null
$openCoverVersion = $null
$openCoverArgument = $null
$output = $null
$path = $null
$testFilter = $null
$reportGeneratorVersion = $null
$reportGeneratorArgument = $null

$outputDirectory = $null
$nunitReport = $null
$openCoverReport = $null
$reportGeneratorHtml = $null

function Init
{
    $Global:Error.Clear()
    $script:argument = $null
    $script:clean = $false
    $script:coverageFilter = $null
    $script:disableCodeCoverage = $false
    $script:failed = $false
    $script:framework = $null
    $script:initialize = $null
    $script:openCoverVersion = $null
    $script:openCoverArgument = $null
    $script:output = $null
    $script:path = $null
    $script:testFilter = $null
    $script:reportGeneratorVersion = $null
    $script:reportGeneratorArgument = $null

    $script:outputDirectory = Join-Path -Path $TestDrive -ChildPath '.output'
}

function Get-NunitXmlElement
{
    param(
        $Element
    )

    Get-ChildItem -Path $outputDirectory -Filter 'nunit3*.xml' |
        Get-Content -Raw |
        ForEach-Object { 
            $testResult = [xml]$_
            $testResult.SelectNodes(('//{0}' -f $Element))
        }
}

function GivenArgument
{
    param(
        $Argument
    )
    $script:argument = $Argument
}

function GivenClean
{
    $script:clean = $true
}

function GivenInitialize
{
    $script:initialize = $true
}

function GivenCoverageFilter
{
    param(
        $Filter
    )

    $script:coverageFilter = $Filter
}

function GivenDisableCodeCoverage
{
    $script:disableCodeCoverage = $true
}

function GivenOpenCoverVersion
{
    param(
        $Version
    )

    $script:openCoverVersion = $Version
}

function GivenOpenCoverArgument
{
    param(
        $Argument
    )

    $script:openCoverArgument = $Argument
}

function GivenPath
{
    param(
        $Path
    )

    $script:path = $Path
}
function GivenPassingPath
{
    $script:path = 'NUnit3PassingTest\bin\Debug\NUnit3PassingTest.dll'
}

function GivenFailingPath
{
    $script:path = 'NUnit3FailingTest\bin\Debug\NUnit3FailingTest.dll'
}

function GivenFramework
{
    param(
        $Version
    )

    $script:framework = $Version
}

function GivenTestFilter
{
    param(
        $Filter
    )

    $script:testFilter = $Filter
}
function GivenReportGeneratorVersion
{
    param(
        $Version
    )

    $script:reportGeneratorVersion = $Version
}

function GivenReportGeneratorArgument
{
    param(
        $Argument
    )

    $script:reportGeneratorArgument = $Argument
}

function WhenRunningTask
{
    [CmdletBinding()]
    param()

    $taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $buildRoot -ForOutputDirectory $outputDirectory

    $taskParameter = @{}

    if ($path)
    {
        $taskParameter['Path'] = $path
    }

    if ($openCoverVersion)
    {
        $taskParameter['OpenCoverVersion'] = $openCoverVersion
    }

    if ($reportGeneratorVersion)
    {
        $taskParameter['ReportGeneratorVersion'] = $reportGeneratorVersion
    }

    if ($disableCodeCoverage)
    {
        $taskParameter['DisableCodeCoverage'] = $true
    }

    if ($framework)
    {
        $taskParameter['Framework'] = $framework
    }

    if ($argument)
    {
        $taskParameter['Argument'] = $argument
    }

    if ($testFilter)
    {
        $taskParameter['TestFilter'] = $testFilter
    }

    if ($openCoverArgument)
    {
        $taskParameter['OpenCoverArgument'] = $openCoverArgument
    }

    if ($reportGeneratorArgument)
    {
        $taskParameter['ReportGeneratorArgument'] = $reportGeneratorArgument
    }

    if ($coverageFilter)
    {
        $taskParameter['CoverageFilter'] = $coverageFilter
    }

    if ($clean)
    {
        $taskContext.RunMode = 'Clean'
        
        # Ensure we have packages to cleanup in when run in Clean mode
        Install-WhiskeyTool -NuGetPackageName 'NUnit.ConsoleRunner' -Version '3.7.0' -DownloadRoot $buildRoot
        Install-WhiskeyTool -NuGetPackageName 'OpenCover' -Version $openCoverVersion -DownloadRoot $buildRoot
        Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -Version $reportGeneratorVersion -DownloadRoot $buildRoot
        # Install an extra version so we can make sure only specified versions get cleaned up
        Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -Version '2.5.8' -DownloadRoot $buildRoot
    }

    if ($initialize)
    {
        $taskContext.RunMode = 'Initialize'

        Remove-Item -Path (Join-Path -Path $buildRoot -ChildPath 'packages') -Recurse -Force
    }

    try 
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NUnit3'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }

}

function ThenPackagesCleanedUp
{
    $packagesPath = Join-Path -Path $buildRoot -ChildPath 'packages'

    $nunitPackage = 'NUnit.ConsoleRunner.3.7.0'
    $nunitConsolePath = Join-Path -Path $packagesPath -ChildPath $nunitPackage
    It ('should clean up the {0} package' -f $nunitPackage) {
        $nunitConsolePath | Should -Not -Exist
    }

    $openCoverPackage = 'OpenCover.{0}' -f $openCoverVersion
    $openCoverPath = Join-Path -Path $packagesPath -ChildPath $openCoverPackage
    It ('should clean up the {0} package' -f $openCoverPackage) {
        $openCoverPath | Should -Not -Exist
    }

    $reportGeneratorPackage = 'ReportGenerator.{0}' -f $reportGeneratorVersion
    $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath $reportGeneratorPackage
    It ('should clean up the {0} package'-f $reportGeneratorPackage) {
        $reportGeneratorPath | Should -Not -Exist
    }

    $extraReportGeneratorPath = Join-Path -Path $packagesPath -ChildPath 'ReportGenerator.2.5.8'
    It 'should leave the ReportGenerator.2.5.8 package' {
        $extraReportGeneratorPath | Should -Exist
    }

}

function ThenPackagesDownloaded
{
    $packagesPath = Join-Path -Path $buildRoot -ChildPath 'packages'

    $nunitPackage = 'NUnit.ConsoleRunner.3.7.0'
    $nunitConsolePath = Join-Path -Path $packagesPath -ChildPath $nunitPackage
    It ('should download the {0} package' -f $nunitPackage) {
        $nunitConsolePath | Should -Exist
    }

    $openCoverPackage = 'OpenCover.{0}' -f $openCoverVersion
    $openCoverPath = Join-Path -Path $packagesPath -ChildPath $openCoverPackage
    It ('should download the {0} package' -f $openCoverPackage) {
        $openCoverPath | Should -Exist
    }

    $reportGeneratorPackage = 'ReportGenerator.{0}' -f $reportGeneratorVersion
    $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath $reportGeneratorPackage
    It ('should download the {0} package'-f $reportGeneratorPackage) {
        $reportGeneratorPath | Should -Exist
    }

}

function ThenRanNUnitWithNoHeaderArgument
{
    It 'should run NUnit with additional given arguments' {
        $output[0] | Should -Not -Match 'NUnit Console Runner'
    }
}

function ThenRanWithSpecifiedFramework
{
    $resultFramework = Get-NunitXmlElement -Element 'setting'
    $resultFramework = $resultFramework | Where-Object { $_.name -eq 'RuntimeFramework' } | Select-Object -ExpandProperty 'value'

    It 'should run with specified framework' {
        $resultFramework | Should -Be $framework
    }

}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It ('error message should match [{0}]' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenTaskSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'task should not fail' {
        $failed | Should -Be $false
    }
}

function ThenRanOnlySpecificTest
{
    param(
        $TestName
    )

    $testResults = Get-NunitXmlElement -Element 'test-case'
    $testResultsCount = $testResults.name | Measure-Object | Select-Object -ExpandProperty Count

    $testNameCount = $TestName | Measure-Object | Select-Object -ExpandProperty Count

    It 'should only run specific tests' {
        $testResultsCount | Should -Be $testNameCount

        $testResults.name | ForEach-Object {
            $_ | Should -BeIn $TestName
        }
    }
}

function ThenNUnitReportGenerated
{
    $nunitReport = Get-ChildItem -Path $outputDirectory -Filter 'nunit3-*.xml' -Recurse

    It 'should run NUnit tests' {
        $nunitReport | Should -Not -BeNullOrEmpty
    }

    It 'should write results to report xml file' {
        Get-NunitXmlElement -Element 'test-case' | Should -Not -BeNullOrEmpty
    }
}

function ThenNUnitReportDoesntExist
{
    $nunitReport = Get-ChildItem -Path $outputDirectory -Filter 'nunit3-*.xml' -Recurse

    It 'should not create NUnit report xml' {
        $nunitReport | Should -BeNullOrEmpty
    }
}

function ThenCodeCoverageReportGenerated
{
    $openCoverReport = Get-ChildItem -Path $outputDirectory -Filter 'openCover.xml' -Recurse
    $reportGeneratorHtml = Get-ChildItem -Path $outputDirectory -Filter 'index.htm' -Recurse

    It 'should run OpenCover' {
        $openCoverReport | Should -Not -BeNullOrEmpty
    }

    It 'should run ReportGenerator' {
        $reportGeneratorHtml | Should -Not -BeNullOrEmpty
    }
}

function ThenCodeCoverageReportNotCreated
{
    $openCoverReport = Get-ChildItem -Path $outputDirectory -Filter 'openCover.xml' -Recurse
    $reportGeneratorHtml = Get-ChildItem -Path $outputDirectory -Filter 'index.htm' -Recurse

    It 'should not run OpenCover' {
        $openCoverReport | Should -BeNullOrEmpty
    }

    It 'should not run ReportGenerator' {
        $reportGeneratorHtml | Should -BeNullOrEmpty
    }
}

function ThenNUnitShouldNotRun
{
    $nunitReport = Get-ChildItem -Path $outputDirectory -Filter 'nunit3-*.xml' -Recurse

    It 'should not run NUnit tests' {
        $nunitReport | Should -BeNullOrEmpty
    }
}

function ThenOutput
{
    param(
        $Contains,
        $DoesNotContain
    )

    if ($Contains)
    {
        It ('output should contain [{0}]' -f $Contains) {
            $output -join [Environment]::NewLine | Should -Match $Contains
        }
    }
    else {
        It ('output should not contain [{0}]' -f $DoesNotContain) {
            $output -join [Environment]::NewLine | Should -Not -Match $DoesNotContain
        }
    }
}

function ThenRanWithCoverageFilter
{
    $passingTestResult = Join-Path -Path $outputDirectory -ChildPath 'opencover\NUnit3PassingTest_TestFixture.htm'
    $failingTestResult = Join-Path -Path $outputDirectory -ChildPath 'opencover\NUnit3FailingTest_TestFixture.htm'

    It 'should run OpenCover with given coverage filter' {
        $passingTestResult | Should -Exist
        $failingTestResult | Should -Not -Exist
    }
}

Describe 'Invoke-WhiskeyNUnit3Task.when running in Clean mode' {
    Init
    GivenOpenCoverVersion '4.6.519'
    GivenReportGeneratorVersion '2.5.11'
    GivenClean
    WhenRunningTask
    ThenPackagesCleanedUp
    ThenNUnitShouldNotRun
    ThenCodeCoverageReportNotCreated
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running in Initialize mode' {
    Init
    GivenOpenCoverVersion '4.6.519'
    GivenReportGeneratorVersion '2.5.11'
    GivenInitialize
    WhenRunningTask
    ThenPackagesDownloaded
    ThenNUnitShouldNotRun
    ThenCodeCoverageReportNotCreated
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when missing Path paramter' {
    Init
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'Property ''Path'' is mandatory. It should be one or more paths to the assemblies whose tests should be run' 
}

Describe 'Invoke-WhiskeyNUnit3Task.when given bad Path' {
    Init
    GivenPath 'NUnit3PassingTest\bin\Debug\NUnit3FailingTest.dll','nonexistentfile'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'does not exist.'
}

Describe 'Invoke-WhiskeyNUnit3Task.when NUnit fails to install' {
    Init
    GivenPassingPath
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -match 'NUnit.ConsoleRunner' }
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'failed to install.'
}

Describe 'Invoke-WhiskeyNUnit3Task.when nunit3-console.exe cannot be located' {
    Init
    GivenPassingPath
    Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -ParameterFilter { $ChildPath -match 'nunit3-console.exe' } -MockWith { 'C:\some\nonexistent\path\nunit3-console.exe' }
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'could not locate ''nunit3-console.exe'''
}

Describe 'Invoke-WhiskeyNUnit3Task.when OpenCover fails to install' {
    Init
    GivenPassingPath
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -match 'OpenCover'}
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'failed to install.'
}

Describe 'Invoke-WhiskeyNUnit3Task.when ReportGenerator fails to install' {
    Init
    GivenPassingPath
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -match 'ReportGenerator'}
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'failed to install.'
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with disabled code coverage' {
    Init
    GivenPassingPath
    GivenDisableCodeCoverage
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportNotCreated
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with multiple paths' {
    Init
    GivenPath 'NUnit3PassingTest\bin\Debug\NUnit3PassingTest.dll','NUnit3PassingTest\bin\Debug\NUnit3PassingTest.dll'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running failing NUnit tests' {
    Init
    GivenPath 'NUnit3FailingTest\bin\Debug\NUnit3FailingTest.dll', 'NUnit3PassingTest\bin\Debug\NUnit3PassingTest.dll'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenTaskFailedWithMessage 'NUnit3 tests failed'
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with specific framework' {
    Init
    GivenPassingPath
    GivenFramework '4.5'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenRanWithSpecifiedFramework
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit with extra arguments' {
    Init
    GivenPassingPath
    GivenArgument '--noheader','--dispose-runners'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenRanNUnitWithNoHeaderArgument
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit with bad arguments' {
    Init
    GivenPassingPath
    GivenArgument '-badarg'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNUnitReportDoesntExist
    ThenTaskFailedWithMessage 'NUnit3 didn''t run successfully'
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit with a test filter' {
    Init
    GivenPassingPath
    GivenTestFilter "cat == 'Category with Spaces 1'"
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenRanOnlySpecificTest 'HasCategory1'
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit with multiple test filters' {
    Init
    GivenPassingPath
    GivenTestFilter "cat == 'Category with Spaces 1'", "cat == 'Category with Spaces 2'"
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenRanOnlySpecificTest 'HasCategory1','HasCategory2'
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with OpenCover argument' {
    Init
    GivenPassingPath
    GivenOpenCoverArgument '-showunvisited'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenOutput -Contains '====Unvisited Classes===='
    ThenTaskSucceeded
}
Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with OpenCover coverage filter' {
    Init
    GivenPath 'NUnit3FailingTest\bin\Debug\NUnit3FailingTest.dll', 'NUnit3PassingTest\bin\Debug\NUnit3PassingTest.dll'
    GivenCoverageFilter '-[NUnit3FailingTest]*','+[NUnit3PassingTest]*'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenRanWithCoverageFilter
}

Describe 'Invoke-WhiskeyNUnit3Task.when running NUnit tests with ReportGenerator argument' {
    Init
    GivenPassingPath
    GivenReportGeneratorArgument '-verbosity:off'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenOutput -DoesNotContain 'Initializing report builders'
    ThenTaskSucceeded
}
