Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# OpenCover hangs when run on .NET 4.6.2.
$skip = (Test-Path -Path 'env:APPVEYOR_*') -and $env:APPVEYOR_BUILD_WORKER_IMAGE -eq 'Visual Studio 2013'

# Build the assemblies that use NUnit3. Only do this once.
$latestNUnit3Version = '3.10.0'
$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
$packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
$argument = $null
$clean = $false
$coverageFilter = $null
$disableCodeCoverage = $false
$failed = $false
$framework = $null
$targetResultFormat = $null
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
    $script:targetResultFormat = $null
    $script:initialize = $null
    $script:openCoverVersion = $null
    $script:openCoverArgument = $null
    $script:output = $null
    $script:path = $null
    $script:testFilter = $null
    $script:reportGeneratorVersion = $null
    $script:reportGeneratorArgument = $null
    $script:nunitVersion = $null
    $script:supportNUnit2 = $false

    $script:buildRoot = $TestDrive.FullName

    $script:outputDirectory = Join-Path -Path $buildRoot -ChildPath '.output'

    # Test assemblies in separate folders to avoid cross-reference of NUnit Framework assembly versions
    @(3, 2) | ForEach-Object  {
        New-Item (Join-Path $buildRoot "NUnit$($_)Tests") -Type Directory
        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath "Assemblies\NUnit$($_)*Test\bin\*\*") `
            -Destination (Join-Path $buildRoot "NUnit$($_)Tests")
    }
}

function Get-GeneratedNUnitReport {
    param(
        $ResultFormat = 'nunit3'
    )

    return Get-ChildItem -Path $outputDirectory -Filter "$($ResultFormat)*.xml"
}

function Get-NunitXmlElement
{
    param(
        $ReportFile,
        $Element
    )

    Get-Content $reportFile.FullName -Raw |
        ForEach-Object {
            $testResult = [xml]$_
            $testResult.SelectNodes(('//{0}' -f $Element))
        }
}

function Get-PassingTestPath
{
    return Join-Path 'NUnit3Tests' 'NUnit3PassingTest.dll'
}

function Get-PassingNUnit2TestPath
{
    return Join-Path 'NUnit2Tests' 'NUnit2PassingTest.dll'
}

function Get-FailingTestPath
{
    return Join-Path 'NUnit3Tests' 'NUnit3FailingTest.dll'
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
    GivenPath (Get-PassingTestPath)
}

function GivenFailingPath
{
    GivenPath (Get-FailingTestPath)
}

function GivenFramework
{
    param(
        $Version
    )

    $script:framework = $Version
}

function GivenResultFormat
{
    param(
        $ResultFormat
    )

    $script:targetResultFormat = $ResultFormat
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
        [switch]$InCleanMode
    )

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

    if ($targetResultFormat)
    {
        $taskParameter['ResultFormat'] = $targetResultFormat
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
    }

    if ($initialize)
    {
        $taskContext.RunMode = 'Initialize'
    }

    Mock -CommandName 'Install-WhiskeyTool' -Module 'Whiskey' -MockWith {
        return (Join-Path -Path $DownloadRoot -ChildPath ('packages\{0}.*' -f $NuGetPackageName)) |
                    Get-Item -ErrorAction Ignore |
                    Select-Object -First 1 |
                    Select-Object -ExpandProperty 'FullName'
    }

    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'

    Copy-Item -Path $packagesRoot -Destination $buildRoot -Recurse -ErrorAction Ignore

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
        $PackageName,
        $Version
    )

    Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter {
        # $DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('NuGetPackageName  expected  {0}' -f $PackageName)
        Write-WhiskeyDebug -Message ('                  actual    {0}' -f $NuGetPackageName)
        $NuGetPackageName -eq $PackageName
    }
    if( $Version )
    {
        $expectedVersion = $Version
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Version -eq $expectedVersion }
    }
}

function ThenPackageNotInstalled
{
    param(
        $PackageName
    )

    Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -eq $PackageName } -Times 0
}

function ThenPackageUninstalled
{
    param(
        $PackageName,
        $Version
    )

    Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -eq $PackageName }
    $expectedVersion = $Version
    Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Version -eq $expectedVersion }
}

function ThenRanNUnitWithNoHeaderArgument
{
    $output[0] | Should -Not -Match 'NUnit Console Runner'
}

function ThenRanWithSpecifiedFramework
{
    $nunitReport = Get-GeneratedNUnitReport

    $resultFramework = Get-NunitXmlElement -ReportFile $nunitReport -Element 'setting'
    $resultFramework = $resultFramework | Where-Object { $_.name -eq 'RuntimeFramework' } | Select-Object -ExpandProperty 'value'

    $resultFramework | Should -Be $framework
}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    $failed | Should -BeTrue
    $Global:Error[0] | Should -Match $Message
}

function ThenTaskSucceeded
{
    $Global:Error | Should -BeNullOrEmpty
    $failed | Should -BeFalse
}

function ThenRanOnlySpecificTest
{
    param(
        $TestName
    )

    $nunitReport = Get-GeneratedNUnitReport

    $testResults = Get-NunitXmlElement -ReportFile $nunitReport -Element 'test-case'
    $testResultsCount = $testResults.name | Measure-Object | Select-Object -ExpandProperty Count

    $testNameCount = $TestName | Measure-Object | Select-Object -ExpandProperty Count

    $testResultsCount | Should -Be $testNameCount

    $testResults.name | ForEach-Object {
        $_ | Should -BeIn $TestName
    }
}

function ThenNUnitReportGenerated
{
    param(
        $ResultFormat = 'nunit3'
    )

    $nunitReport = Get-GeneratedNUnitReport -ResultFormat $ResultFormat

    $nunitReport | Should -Not -BeNullOrEmpty -Because 'test results should be saved'
    $nunitReport | Select-Object -ExpandProperty 'Name' | Should -Match "^$($ResultFormat)\+.{8}\..{3}\.xml"
    if ($ResultFormat -eq 'nunit3') 
    {
        Get-NunitXmlElement -ReportFile $nunitReport -Element 'test-run' | Should -Not -BeNullOrEmpty
    }
    else
    {
        Get-NunitXmlElement -ReportFile $nunitReport -Element 'test-results' | Should -Not -BeNullOrEmpty
    }
    Get-NunitXmlElement -ReportFile $nunitReport -Element 'test-case' | Should -Not -BeNullOrEmpty
}

function ThenCodeCoverageReportGenerated
{
    $openCoverReport = Get-ChildItem -Path $outputDirectory -Filter 'openCover.xml' -Recurse
    $reportGeneratorHtml = Get-ChildItem -Path $outputDirectory -Filter 'index.htm' -Recurse
    $openCoverReport | Should -Not -BeNullOrEmpty
    $reportGeneratorHtml | Should -Not -BeNullOrEmpty
}

function ThenCodeCoverageReportNotCreated
{
    $openCoverReport = Get-ChildItem -Path $outputDirectory -Filter 'openCover.xml' -Recurse
    $reportGeneratorHtml = Get-ChildItem -Path $outputDirectory -Filter 'index.htm' -Recurse
    $openCoverReport | Should -BeNullOrEmpty
    $reportGeneratorHtml | Should -BeNullOrEmpty
}

function ThenNUnitShouldNotRun
{
    $nunitReport = Get-GeneratedNUnitReport
    $nunitReport | Should -BeNullOrEmpty -Because 'test results should not be saved if NUnit does not run'
}

function ThenOutput
{
    param(
        $Contains,
        $DoesNotContain
    )

    if ($Contains)
    {
        $output -join [Environment]::NewLine | Should -Match $Contains
    }
    else {
        $output -join [Environment]::NewLine | Should -Not -Match $DoesNotContain
    }
}

function ThenRanWithCoverageFilter
{
    $passingTestResult = Join-Path -Path $outputDirectory -ChildPath 'opencover\NUnit3PassingTest_TestFixture.htm'
    $failingTestResult = Join-Path -Path $outputDirectory -ChildPath 'opencover\NUnit3FailingTest_TestFixture.htm'
    $passingTestResult | Should -Exist
    $failingTestResult | Should -Not -Exist
}

if( -not $IsWindows )
{
    Describe 'NUnit3.when run on non-Windows platform' {
        It 'should fail' {
            Init
            WhenRunningTask -ErrorAction SilentlyContinue
            ThenTaskFailedWithMessage 'Windows\ platform'
        }
    }
    return
}

$taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit3.yml')
try
{
    Invoke-WhiskeyBuild -Context $taskContext
}
finally
{
    $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose
}

Remove-Item -Path $packagesRoot -Recurse -Force -ErrorAction Ignore
& $nugetPath install OpenCover -OutputDirectory $packagesRoot
& $nugetPath install ReportGenerator -OutputDirectory $packagesRoot
& $nugetPath install NUnit.ConsoleRunner -Version $latestNUnit3Version -OutputDirectory $packagesRoot
& $nugetPath install NUnit.Console -Version $latestNUnit3Version -OutputDirectory $packagesRoot

Describe 'NUnit3.when running in Clean mode' {
    It 'should remove existing tool packages' {
        Init
        GivenOpenCoverVersion
        GivenReportGeneratorVersion
        WhenRunningTask -InCleanMode
        ThenPackageUninstalled 'NUnit.Console' $latestNUnit3Version
        ThenPackageUninstalled 'NUnit.ConsoleRunner' $latestNUnit3Version
        ThenPackageUninstalled 'OpenCover' $openCoverVersion
        ThenPackageUninstalled 'ReportGenerator' $reportGeneratorVersion
        ThenNUnitShouldNotRun
        ThenCodeCoverageReportNotCreated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running in Initialize mode' {
    It 'should install packages but not run any tests' {
        Init
        GivenOpenCoverVersion
        GivenReportGeneratorVersion
        GivenInitialize
        WhenRunningTask
        ThenPackageInstalled 'NUnit.Console' $latestNUnit3Version
        ThenPackageInstalled 'NUnit.ConsoleRunner' $latestNUnit3Version
        ThenPackageInstalled 'OpenCover' $openCoverVersion
        ThenPackageInstalled 'ReportGenerator' $reportGeneratorVersion
        ThenNUnitShouldNotRun
        ThenCodeCoverageReportNotCreated
        ThenTaskSucceeded
    }	
}

Describe 'NUnit3.when missing Path parameter' {
    It 'should fail' {
        Init
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'Property "Path" is mandatory'
    }
}

Describe 'NUnit3.when given bad Path' {
    It 'should fail' {
        Init
        GivenPath 'NUnit3PassingTest\bin\Debug\NUnit3FailingTest.dll', 'nonexistentfile'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'does not exist.'
    }
}

Describe 'NUnit3.when module fails to install' {
    foreach ($package in @('NUnit.Console', 'NUnit.ConsoleRunner', 'OpenCover', 'ReportGenerator'))
    {
        Context ('for missing "{0}" module' -f $package) {
            It 'should fail' {
                Init
                Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $NuGetPackageName -eq $package }
                WhenRunningTask -ErrorAction SilentlyContinue
                ThenTaskFailedWithMessage ('"{0}" failed to install.' -f $package)
            }
        }
    }
}

Describe 'NUnit3.when module executables cannot be found' {
    foreach ($executable in @('nunit3-console.exe', 'OpenCover.Console.exe', 'ReportGenerator.exe'))
    {
        Context ('for missing "{0}" executable' -f $executable) {
            It 'should fail' {
                Init
                Mock -CommandName 'Get-ChildItem' -ModuleName 'Whiskey' -ParameterFilter { $Filter -eq $executable }
                WhenRunningTask -ErrorAction SilentlyContinue
                ThenTaskFailedWithMessage ('Unable to find "{0}"' -f $executable)
            }
        }
    }
}

Describe 'NUnit3.when running NUnit tests with disabled code coverage' {
    It 'should run NUnit directly' {
        Init
        GivenPassingPath
        GivenDisableCodeCoverage
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportNotCreated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit tests with multiple paths' {
    It 'should run tests in each path' -Skip:$skip {
        Init
        GivenPath (Get-PassingTestPath), (Get-PassingTestPath)
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running failing NUnit tests' {
    It 'should fail the build' -Skip:$skip {
        Init
        GivenPath (Get-FailingTestPath), (Get-PassingTestPath)
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenTaskFailedWithMessage 'NUnit3 tests failed'
    }
}

Describe 'NUnit3.when running NUnit tests with specific framework' {
    It 'should run tests with that dotNET framework' -Skip:$skip {
        Init
        GivenPassingPath
        GivenFramework '4.5'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenRanWithSpecifiedFramework
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit2 tests generating NUnit3 output' {
    It 'should generate nunit3 output' -Skip:$skip {
        Init
        GivenPath (Get-PassingNUnit2TestPath)
        WhenRunningTask
        ThenNUnitReportGenerated 
        ThenCodeCoverageReportGenerated 
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit2 tests generating NUnit2 output' {
    It 'should generate nunit2 output' -Skip:$skip {
        Init
        GivenPath (Get-PassingNUnit2TestPath)
        GivenResultFormat 'nunit2'
        WhenRunningTask
        ThenNUnitReportGenerated -ResultFormat 'nunit2'
        ThenCodeCoverageReportGenerated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with extra arguments' {
    It 'should run NUnit with those arguments' -Skip:$skip {
        Init
        GivenPassingPath
        GivenArgument '--noheader','--dispose-runners'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenRanNUnitWithNoHeaderArgument
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with bad arguments' {
    It 'should pass bad args to NUnit and fail' -Skip:$skip {
        Init
        GivenPassingPath
        GivenArgument '-badarg'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitShouldNotRun
        ThenTaskFailedWithMessage 'NUnit3 didn''t run successfully'
    }
}

Describe 'NUnit3.when running NUnit with a test filter' {
    It 'should pass test filter to NUnit' -Skip:$skip {
        Init
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with multiple test filters' {
    It 'should pass all test filters' -Skip:$skip {
        Init
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'", "cat == 'Category with Spaces 2'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1','HasCategory2'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit tests with OpenCover argument' {
    It 'should pass argument to OpenCover' -Skip {
        Init
        GivenPassingPath
        GivenOpenCoverArgument '-showunvisited'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenOutput -Contains '====Unvisited Classes===='
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit tests with OpenCover coverage filter' {
    It 'should pass coverage filter to OpenCover' -Skip {
        Init
        GivenPath (Get-FailingTestPath), (Get-PassingTestPath)
        GivenCoverageFilter '-[NUnit3FailingTest]*','+[NUnit3PassingTest]*'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenRanWithCoverageFilter
    }
}

Describe 'NUnit3.when running NUnit tests with ReportGenerator argument' {
    It 'should pass ReportGenerator argument' -Skip:$skip {
        Init
        GivenPassingPath
        GivenReportGeneratorArgument '-verbosity:off'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenCodeCoverageReportGenerated
        ThenOutput -DoesNotContain 'Initializing report builders'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when using custom version of NUnit 3' {
    It 'should download that version of NUnit' -Skip:$skip {
        Init
        GivenPassingPath
        GivenVersion '3.2.1'
        WhenRunningTask
        ThenPackageInstalled 'NUnit.ConsoleRunner' '3.2.1'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when using a non-3 version of NUnit' {
    It 'should fail' -Skip:$skip {
        Init
        GivenPassingPath
        GivenVersion '2.6.4'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenPackageNotInstalled 'NUnit.ConsoleRunner'
        ThenTaskFailedWithMessage 'isn''t\ a\ valid\ 3\.x\ version\ of\ NUnit'
    }
}