Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# Build the assemblies that use NUnit3. Only do this once.
$latestNUnit3Version = '3.7.0'
$taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit3.yml')
Invoke-WhiskeyBuild -Context $taskContext

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
    $script:nunitVersion = $null

    $script:buildRoot = $TestDrive.FullName

    $script:outputDirectory = Join-Path -Path $buildRoot -ChildPath '.output'

    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit3*\bin\*\*') -Destination $buildRoot
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
    $script:path = 'NUnit3PassingTest.dll'
}

function GivenFailingPath
{
    $script:path = 'NUnit3FailingTest.dll'
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

function GivenPackageInstalled
{
    param(
        $Name,
        $Version
    )

    $versionParam = @{ }
    if( $Version )
    {
        $versionParam['Version'] = $Version
    }

    Install-WhiskeyTool -NuGetPackageName $Name @versionParam -DownloadRoot $buildRoot
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

function GivenVersion
{
    param(
        $Version
    )

    $script:nunitVersion = $Version
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $InCleanMode
    )

    $taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $TestDrive.FullName -ForOutputDirectory $outputDirectory

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

    if( $nunitVersion )
    {
        $taskParameter['Version'] = $nunitVersion
    }

    if ($InCleanMode)
    {
        $taskContext.RunMode = 'Clean'
        
        ## Ensure we have packages to cleanup in when run in Clean mode
        #Install-WhiskeyTool -NuGetPackageName 'NUnit.ConsoleRunner' -Version '3.7.0' -DownloadRoot $buildRoot
        #Install-WhiskeyTool -NuGetPackageName 'OpenCover' -Version $openCoverVersion -DownloadRoot $buildRoot
        #Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -Version $reportGeneratorVersion -DownloadRoot $buildRoot
        ## Install an extra version so we can make sure only specified versions get cleaned up
        #Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -Version '2.5.8' -DownloadRoot $buildRoot
    }

    if ($initialize)
    {
        $taskContext.RunMode = 'Initialize'
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

function ThenPackageInstalled
{
    param(
        $PackageDirectoryName
    )

    It ('should not uninstall package ''{0}''' -f $PackageDirectoryName) {
        Join-Path -Path $buildRoot -ChildPath ('packages\{0}' -f $PackageDirectoryName) | Should -Exist
    }
}

function ThenPackageNotInstalled
{
    param(
        $PackageDirectoryName
    )

    It ('should uninstall package ''{0}''' -f $PackageDirectoryName) {
        Join-Path -Path $buildRoot -ChildPath ('packages\{0}' -f $PackageDirectoryName) | Should -Not -Exist
    }
}

function ThenPackagesDownloaded
{
    ThenPackageInstalled ('NUnit.ConsoleRunner.{0}' -f $latestNUnit3Version)
    ThenPackageInstalled ('OpenCover.{0}' -f $openCoverVersion)
    ThenPackageInstalled ('ReportGenerator.{0}' -f $reportGeneratorVersion)
}

function ThenPackageInstalled
{
    param(
        $Name
    )

    It ('package ''{0}'' should exist' -f $Name) {
        Join-Path -Path $buildRoot -ChildPath ('packages\{0}' -f $Name) | Should -Exist
    }
}

function ThenPackageNotInstalled
{
    param(
        $Name
    )

    It ('package ''{0}'' should not exist' -f $Name) {
        Join-Path -Path $buildRoot -ChildPath ('packages\{0}' -f $Name) | Should -Not -Exist
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
    GivenPackageInstalled 'NUnit.ConsoleRunner'
    GivenPackageInstalled 'OpenCover' '4.6.519'
    GivenPackageInstalled 'ReportGenerator' '2.5.11'
    GivenPackageInstalled 'ReportGenerator' '2.5.8'
    WhenRunningTask -InCleanMode
    ThenPackageNotInstalled ('NUnit.ConsoleRunner.{0}' -f $latestNUnit3Version)
    ThenPackageNotInstalled 'OpenCover.4.6.519'
    ThenPackageNotInstalled 'ReportGenerator.2.5.11'
    ThenPackageInstalled 'ReportGenerator.2.5.8'
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

Describe 'Invoke-WhiskeyNUnit3Task.when missing Path parameter' {
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
    GivenPath 'NUnit3PassingTest.dll','NUnit3PassingTest.dll'
    WhenRunningTask
    ThenNUnitReportGenerated
    ThenCodeCoverageReportGenerated
    ThenTaskSucceeded
}

Describe 'Invoke-WhiskeyNUnit3Task.when running failing NUnit tests' {
    Init
    GivenPath 'NUnit3FailingTest.dll', 'NUnit3PassingTest.dll'
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
    GivenPath 'NUnit3FailingTest.dll', 'NUnit3PassingTest.dll'
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

Describe 'NUnit3.when using custom version of NUnit 3' {
    Init
    GivenPassingPath
    GivenVersion '3.2.1'
    WhenRunningTask
    ThenPackageInstalled 'NUnit.ConsoleRunner.3.2.1'
    ThenTaskSucceeded
}

Describe 'NUnit3.when using a non-3 version of NUnit' {
    Init
    GivenPassingPath
    GivenVersion '2.6.4'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenPackageNotInstalled 'NUnit.ConsoleRunner.*'
    ThenTaskFailedWithMessage 'isn''t\ a\ valid\ 3\.x\ version\ of\ NUnit'
}