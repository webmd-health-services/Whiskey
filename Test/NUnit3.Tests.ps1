Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# Build the assemblies that use NUnit3. Only do this once.
$latestNUnit3Version =
    Find-Package -Name 'NUnit.Runners' -AllVersions |
    Where-Object 'Version' -Like '3.*' |
    Where-Object 'Version' -NotLike '*-*' |
    Select-Object -First 1 |
    Select-Object -ExpandProperty 'Version'

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
$packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
Remove-Item -Path $packagesRoot -Recurse -Force -ErrorAction Ignore
& $nugetPath install 'NUnit.Runners' -Version $latestNUnit3Version -OutputDirectory $packagesRoot
& $nugetPath install 'NUnit.Console' -Version $latestNUnit3Version -OutputDirectory $packagesRoot

$argument = $null
$failed = $false
$framework = $null
$targetResultFormat = $null
$initialize = $null
$output = $null
$path = $null
$testFilter = $null

$outputDirectory = $null
$nunitReport = $null

function Init
{
    $Global:Error.Clear()
    $script:argument = $null
    $script:failed = $false
    $script:framework = $null
    $script:targetResultFormat = $null
    $script:initialize = $null
    $script:output = $null
    $script:path = $null
    $script:testFilter = $null
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

function Get-GeneratedNUnitReport
{
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
    )

    $taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $buildRoot -ForOutputDirectory $outputDirectory

    $taskParameter = @{}

    if ($path)
    {
        $taskParameter['Path'] = $path
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

    if( $nunitVersion )
    {
        $taskParameter['Version'] = $nunitVersion
    }

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
        $Version = '*'
    )

    Join-Path -Path $buildRoot -ChildPath "packages\$($PackageName).$($Version)" | Should -Exist
}

function ThenPackageNotInstalled
{
    param(
        $PackageName
    )

    Join-Path -Path $buildRoot -ChildPath "packages\$($PackageName).*" | Should -Not -Exist
}

function ThenRanNUnitWithNoHeaderArgument
{
    $output[0] | Should -Not -Match 'NUnit Console Runner'
}

function ThenRanWithSpecifiedFramework
{
    param(
        [String] $ExpectedFramework
    )

    $nunitReport = Get-GeneratedNUnitReport

    $resultFramework = Get-NunitXmlElement -ReportFile $nunitReport -Element 'setting'
    $resultFramework =
        $resultFramework |
        Where-Object { $_.name -eq 'TargetRuntimeFramework' } |
        Select-Object -ExpandProperty 'value'

    $resultFramework | Should -Be $ExpectedFramework
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

It 'should fail' {
        Describe 'NUnit3.when missing Path parameter' {
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

Describe 'NUnit3.when module executables cannot be found' {
    foreach ($executable in @('nunit3-console.exe'))
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

Describe 'NUnit3.when running NUnit tests' {
    It 'should run NUnit' {
        Init
        GivenPassingPath
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit tests with multiple paths' {
    It 'should run tests in each path' {
        Init
        GivenPath (Get-PassingTestPath), (Get-PassingTestPath)
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running failing NUnit tests' {
    It 'should fail the build' {
        Init
        GivenPath (Get-FailingTestPath), (Get-PassingTestPath)
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitReportGenerated
        ThenTaskFailedWithMessage 'NUnit tests failed'
    }
}

Describe 'NUnit3.when running NUnit tests with specific framework' {
    It 'should run tests with that dotNET framework' {
        Init
        GivenPassingPath
        GivenFramework 'net-4.5'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanWithSpecifiedFramework 'net-4.5'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit2 tests generating NUnit3 output' {
    It 'should generate nunit3 output' {
        Init
        GivenPath (Get-PassingNUnit2TestPath)
        WhenRunningTask
        ThenNUnitReportGenerated 
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit2 tests generating NUnit2 output' {
    It 'should generate nunit2 output' {
        Init
        GivenPath (Get-PassingNUnit2TestPath)
        GivenResultFormat 'nunit2'
        WhenRunningTask
        ThenNUnitReportGenerated -ResultFormat 'nunit2'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with extra arguments' {
    It 'should run NUnit with those arguments' {
        Init
        GivenPassingPath
        GivenArgument '--noheader','--dispose-runners'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanNUnitWithNoHeaderArgument
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with bad arguments' {
    It 'should pass bad args to NUnit and fail' {
        Init
        GivenPassingPath
        GivenArgument '-badarg'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitShouldNotRun
        ThenTaskFailedWithMessage 'NUnit didn''t run successfully'
    }
}

Describe 'NUnit3.when running NUnit with a test filter' {
    It 'should pass test filter to NUnit' {
        Init
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when running NUnit with multiple test filters' {
    It 'should pass all test filters' {
        Init
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'", "cat == 'Category with Spaces 2'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1','HasCategory2'
        ThenTaskSucceeded
    }
}

Describe 'NUnit3.when using custom version of NUnit 3' {
    It 'should download that version of NUnit' {
        Init
        GivenPassingPath
        GivenVersion '3.2.1'
        WhenRunningTask
        ThenPackageInstalled 'NUnit.ConsoleRunner' '3.2.1'
    }
}
