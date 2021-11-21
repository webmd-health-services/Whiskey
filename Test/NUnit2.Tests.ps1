
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

# OpenCover hangs when run on .NET 4.6.2.
$skip = (Test-Path -Path 'env:APPVEYOR_*') -and $env:APPVEYOR_BUILD_WORKER_IMAGE -eq 'Visual Studio 2013'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
$packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'

$latestNUnit2Version = '2.6.4'

function Assert-NUnitTestsRun
{
    param(
        [String]$ReportPath
    )
    $reports = $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml'
    $reports | Should -Not -BeNullOrEmpty

    $reports | Select-Object -ExpandProperty 'Name' | Should -Match '^nunit2\+.{8}\..{3}\.xml$'
}

function Assert-NUnitTestsNotRun
{
    param(
        [String]$ReportPath
    )
    $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml' | Should -BeNullOrEmpty
}

function Assert-OpenCoverRuns
{
    param(
        [String]$OpenCoverDirectoryPath
    )
    $openCoverFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'openCover.xml'
    $reportGeneratorFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'index.htm'
    $openCoverFilePath | Should -Exist
    $reportGeneratorFilePath | Should -Exist
}

function Assert-OpenCoverNotRun
{
    param(
        [String]$OpenCoverDirectoryPath
    )
    $openCoverFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'openCover.xml'
    $reportGeneratorFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'index.htm'
    $openCoverFilePath | Should -Not -Exist
    $reportGeneratorFilePath | Should -Not -Exist
}

function Invoke-NUnitTask
{

    [CmdletBinding()]
    param(
        [switch]$ThatFails,

        [switch]$WithNoPath,

        [switch]$WithInvalidPath,

        [switch]$WhenJoinPathResolveFails,

        [switch]$WithFailingTests,

        [switch]$WithRunningTests,

        [String]$WithError,

        [switch]$WhenRunningClean,

        [switch]$WhenRunningInitialize,

        [switch]$WithDisabledCodeCoverage,

        [String[]]$CoverageFilter,

        [scriptblock]$MockInstallWhiskeyToolWith
    )

    process
    {

        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName
        Copy-Item -Path $packagesRoot -Destination $TestDrive.FullName -Recurse -ErrorAction Ignore

        if( -not $MockInstallWhiskeyToolWith )
        {
            $MockInstallWhiskeyToolWith = {
                if( -not $Version )
                {
                    $Version = '*'
                }
                return (Join-Path -Path $DownloadRoot -ChildPath ('packages\{0}.{1}' -f $NuGetPackageName,$Version))
            }
        }

        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith $MockInstallWhiskeyToolWith

        $Global:Error.Clear()

        if( $WithNoPath )
        {
            $taskParameter = @{ }
        }
        elseif( $WithInvalidPath )
        {
            $taskParameter = @{
                                Path = @(
                                            'I\do\not\exist'
                                        )
                              }
        }
        elseif( $WithFailingTests )
        {
            $taskParameter = @{
                                Path = @(
                                            'NUnit2FailingTest.dll'
                                        )
                              }
        }
        else
        {
            $taskParameter = @{
                                Path = @(
                                            ('NUnit2PassingTest.dll'),
                                            ('NUnit2FailingTest.dll')
                                        )
                              }
        }

        if( $WithDisabledCodeCoverage )
        {
            $taskParameter.Add('DisableCodeCoverage', $True)
            #$optionalParams['DisableCodeCoverage'] = $True
        }
        if( $CoverageFilter )
        {
            #$optionalParams['CoverageFilter'] = $CoverageFilter
            $taskParameter.Add('CoverageFilter', $CoverageFilter)
        }
        $script:context = New-WhiskeyTestContext -ForBuildRoot $TestDrive.FullName -ForBuildServer
        if( $WhenRunningClean )
        {
            $context.RunMode = 'Clean'
        }

        $Global:Error.Clear()
        $threwException = $false
        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NUnit2'
        }
        catch
        {
            $threwException = $true
        }

        if ( $WithError )
        {
            if( $WhenJoinPathResolveFails )
            {
                $Global:Error[0] | Should -Match ( $WithError )
            }
            else
            {
                $Global:Error | Should -Match ( $WithError )
            }
        }

        $ReportPath = Join-Path -Path $context.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $context.TaskIndex)
        $openCoverPath = Join-Path -Path $context.OutputDirectory -ChildPath 'OpenCover'
        if( $WhenRunningClean )
        {
            $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
            $nunitPath = Join-Path -Path $packagesPath -ChildPath 'NUnit.Runners.2.6.4'
            $oldNUnitPath = Join-Path -Path $packagesPath -ChildPath 'NUnit.Runners.2.6.3'
            $openCoverPackagePath = Join-Path -Path $packagesPath -ChildPath 'OpenCover.*'
            $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath 'ReportGenerator.*'
            $threwException | Should -BeFalse
            $Global:Error | Should -BeNullorEmpty
            $nunitPath | Should -Not -Exist
            $oldNUnitPath | should -Exist
            $openCoverPackagePath | Should -Not -Exist
            $reportGeneratorPath | Should -Not -Exist
            Uninstall-WhiskeyTool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -BuildRoot $context.BuildRoot
        }
        elseif( $ThatFails )
        {
            $threwException | Should -BeTrue
        }
        else
        {
            (Join-Path -Path $context.BuildRoot -ChildPath 'packages\NUnit.Runners.2.6.4') | Should -Exist
        }
        if( $WithFailingTests -or $WithRunningTests )
        {
            Assert-NUnitTestsRun -ReportPath $ReportPath
            if( -not $WithDisabledCodeCoverage )
            {
                Assert-OpenCoverRuns -OpenCoverDirectoryPath $openCoverPath
            }
            else
            {
                Assert-OpenCoverNotRun -OpenCoverDirectoryPath $openCoverPath
            }
        }
        else
        {
            Assert-NUnitTestsNotRun -ReportPath $reportPath
            Assert-OpenCoverNotRun -OpenCoverDirectoryPath $openCoverPath
        }
        if( $CoverageFilter )
        {
            $plusFilterPath = Join-Path -path $openCoverPath -childpath 'NUnit2PassingTest_TestFixture.htm'
            $minusFilterPath = Join-Path -path $openCoverPath -childpath 'NUnit2FailingTest_TestFixture.htm'
            $plusFilterPath | Should -Exist
            $minusFilterPath | Should -Not -Exist
        }

        Remove-Item -Path $context.OutputDirectory -Recurse -Force
    }
}

function GivenNuGetPackageInstalled
{
    param(
        $Name,
        $AtVersion
    )

    & $nugetPath install $Name -Version $AtVersion -OutputDirectory (Join-Path -Path $TestDrive.FullName -ChildPath 'packages')
}

$solutionToBuild = $null
$assemblyToTest = $null
$output = $null
$context = $null
$threwException = $false
$thrownError = $null
$taskParameter = $null
$openCoverVersion = $null
$reportGeneratorVersion = $null
$nunitVersion = $null
$disableCodeCoverage = $null
$exclude = $null
$include = $null
$CoverageFilter = $null

function GivenPassingTests
{
    $script:solutionToBuild = 'NUnit2PassingTest.sln'
    $script:assemblyToTest = 'NUnit2PassingTest.dll'
    $script:taskParameter = @{ 'Path' = $script:solutionToBuild }
}

function GivenInvalidPath
{
    $script:assemblyToTest = 'I/do/not/exist'
}

function GivenCodeCoverageIsDisabled
{
    $Script:disableCodeCoverage = $true
}

function GivenExclude
{
    param(
        [String[]]$Value
    )
    $script:exclude = $value
}

function GivenInclude
{
    param(
        [String[]]$Value
    )
    $script:include = $value
}

function GivenReportGeneratorVersion
{
    param(
        $Version
    )

    $script:reportGeneratorVersion = $Version
}

function GivenOpenCoverVersion
{
    param(
        $Version
    )

    $script:openCoverVersion = $Version
}

function GivenVersion
{
    param(
        $Version
    )

    $script:nunitVersion = $Version
}

function GivenCoverageFilter
{
    Param(
        [String]$Filter
    )
    $script:CoverageFilter = $Filter
}

function Init
{
    $script:openCoverVersion = $null
    $script:reportGeneratorVersion = $null
    $script:nunitVersion = $null
    $script:include = $null
    $script:exclude = $null
    $Script:disableCodeCoverage = $null

    if( (Test-Path -Path $packagesRoot -PathType Container) )
    {
        Copy-Item -Path $packagesRoot -Destination (Join-Path -Path $TestDrive.FullName -ChildPath 'packages') -Recurse
    }
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName

    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName
    Copy-Item -Path $packagesRoot -Destination $TestDrive.FullName -Recurse -ErrorAction Ignore
}

function WhenRunningTask
{
    param(
        [hashtable]$WithParameters = @{ },

        [switch]$WhenRunningInitialize
    )

    $Global:Error.Clear()
    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $TestDrive.FullName

    if( $WhenRunningInitialize )
    {
        $context.RunMode = 'initialize'
    }

    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
        return (Join-Path -Path $DownloadRoot -ChildPath ('packages\{0}.*' -f $NuGetPackageName)) |
                    Get-Item -ErrorAction Ignore |
                    Select-Object -First 1 |
                    Select-Object -ExpandProperty 'FullName'
    }

    try
    {
        $WithParameters['Path'] = $assemblyToTest
        if( $openCoverVersion )
        {
            $WithParameters['OpenCoverVersion'] = $openCoverVersion
        }

        if( $reportGeneratorVersion )
        {
            $WithParameters['ReportGeneratorVersion'] = $reportGeneratorVersion
        }
        if( $disableCodeCoverage )
        {
            $WithParameters['DisableCodeCoverage'] = $disableCodeCoverage
        }
        if( $CoverageFilter )
        {
            $WithParameters['CoverageFilter'] = $CoverageFilter
        }
        if( $exclude )
        {
            $WithParameters['exclude'] = $exclude
        }
        if( $include )
        {
            $WithParameters['include'] = $include
        }
        if( $nunitVersion )
        {
            $WithParameters['Version'] = $nunitVersion
        }
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameters -Name 'NUnit2' 
        $output | Write-WhiskeyVerbose -Context $context
        $script:threwException = $false
        $script:thrownError = $null
    }
    catch
    {
        $script:threwException = $true
        $script:thrownError = $_
    }
}

function Get-TestCaseResult
{
    [OutputType([System.Xml.XmlElement])]
    param(
        [String]$TestName
    )

    Get-ChildItem -Path $context.OutputDirectory -Filter 'nunit2*.xml' |
        Get-Content -Raw |
            ForEach-Object {
                $testResult = [xml]$_
                $testResult.SelectNodes(('//test-case[contains(@name,".{0}")]' -f $TestName))
            }
}

function ThenOutput
{
    param(
        [String[]]$Contains,

        [String[]]$DoesNotContain
    )

    foreach( $regex in $Contains )
    {
        $output -join [Environment]::NewLine | Should -Match $regex
    }

    foreach( $regex in $DoesNotContain )
    {
        $output | Should -Not -Match $regex
    }
}

function ThenTestsNotRun
{
    param(
        [String[]]$TestName
    )

    foreach( $name in $TestName )
    {
        Get-TestCaseResult -TestName $name | Should -BeNullOrEmpty
    }
}

function ThenTestsPassed
{
    param(
        [String[]]$TestName
    )

    foreach( $name in $TestName )
    {
        $result = Get-TestCaseResult -TestName $name
        $result.GetAttribute('result') | ForEach-Object { $_ | Should -Be 'Success' }
    }
    Assert-OpenCoverRuns -OpenCoverDirectoryPath (Join-Path -path $Script:context.OutputDirectory -ChildPath 'OpenCover')
}

function ThenItShouldNotRunTests {
    $ReportPath = Join-Path -Path $context.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $context.TaskIndex)

    $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml' | Should -BeNullOrEmpty
}

function ThenItInstalled {
    param (
        [String]$Name,

        [Version]$Version
    )

    $expectedVersion = $Version
    Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('NuGetPackageName  expected  {0}' -f $Name)
        Write-WhiskeyDebug -Message ('                  actual    {0}' -f $NuGetPackageName)
        $NuGetPackageName -eq $Name
    }
    Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Version -eq $ExpectedVersion }
}

function ThenItInstalledReportGenerator {

    $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
    $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath 'ReportGenerator.*'

    $reportGeneratorPath | Should -Exist
}
function ThenErrorIs {
    param(
        $Regex
    )
    Write-host $Global:error
    $Global:Error | Should -Match $Regex
}

function ThenErrorShouldNotBeThrown {
    param(
        $ErrorMessage
    )
    $Global:Error | Where-Object { $_ -match $ErrorMessage } | Should -BeNullOrEmpty
}

function ThenNoErrorShouldBeThrown {
    $openCoverPath = Join-Path -Path $context.OutputDirectory -ChildPath 'OpenCover'
    write-host $Global:Error
    Assert-OpenCoverNotRun -OpenCoverDirectoryPath $openCoverPath
    $Global:error | Should -BeNullOrEmpty
}

if( -not $IsWindows )
{
    Describe 'NUnit2.when run on non-Windows platform' {
        It 'should fail to run' {
            Init
            GivenPassingTests
            WhenRunningTask
            ThenErrorIs 'Windows\ platform'
        }
    }
    return
}

$latestOpenCoverVersion,$latestReportGeneratorVersion = & {
                                                                & $nugetPath list packageid:OpenCover -Source https://www.nuget.org/api/v2/
                                                                & $nugetPath list packageid:ReportGenerator -Source https://www.nuget.org/api/v2/
                                                        } |
                                                        Where-Object { $_ -match ' (\d+\.\d+\.\d+.*)' } |
                                                        ForEach-Object { $Matches[1] }
$packages = @{
                'OpenCover' = $latestOpenCoverVersion;
                'ReportGenerator' = $latestReportGeneratorVersion;
                'NUnit.Runners' = $latestNUnit2Version;
            }
foreach( $packageID in $packages.Keys )
{
    if( -not (Test-Path -Path (Join-Path -Path $packagesRoot -ChildPath ('{0}.{1}' -f $packageID,$packages[$packageID]))) )
    {
        & $nugetPath install $packageID -Version $packages[$packageID] -OutputDirectory $packagesRoot
    }
}

$taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit2.yml')
Invoke-WhiskeyBuild -Context $taskContext

Describe 'NUnit2.when the Clean Switch is active' {
    It 'should remove dependent packages' {
        GivenNuGetPackageInstalled 'NUnit.Runners' -AtVersion '2.6.3'
        Invoke-NUnitTask -WhenRunningClean
    }
}

Describe 'NUnit2.when running NUnit tests' {
    Context 'no code coverage' {
        It 'should run NUnit2 directly' {
            Invoke-NUnitTask -WithRunningTests -WithDisabledCodeCoverage
        }
    }
    Context 'code coverage' {
        It 'should run NUnit through OpenCover' -Skip:$skip {
            Invoke-NUnitTask -WithRunningTests
        }
    }
}

Describe 'NUnit2.when running failing NUnit2 tests' {
    $withError = [regex]::Escape('NUnit2 tests failed')
    Context 'no code coverage' {
        It 'should run NUnit directly' {
            Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError -WithDisabledCodeCoverage
        }
    }
    Context 'code coverage' {
        It 'should run NUnit through OpenCover' -Skip:$skip {
            Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError
        }
    }
}

Describe 'NUnit2.when Install-WhiskeyTool fails' {
    It 'should fail the build' {
        Invoke-NUnitTask -ThatFails -MockInstallWhiskeyToolWith { return $false }
    }
}

Describe 'NUnit2.when Path Parameter is not included' {
    It 'should fail the build' {
        $withError = [regex]::Escape('Property "Path" is mandatory')
        Invoke-NUnitTask -ThatFails -WithNoPath -WithError $withError
    }
}

Describe 'NUnit2.when Path Parameter is invalid' {
    It 'should fail the build' {
        $withError = [regex]::Escape('do not exist.')
        Invoke-NUnitTask -ThatFails -WithInvalidPath -WithError $withError
    }
}

Describe 'NUnit2.when NUnit Console Path is invalid and Join-Path -resolve fails' {
    It 'should fail the build' {
        Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -MockWith { Write-Error 'Path does not exist!' } -ParameterFilter { $ChildPath -eq 'nunit-console.exe' }
        $withError = [regex]::Escape('was installed, but couldn''t find nunit-console.exe')
        Invoke-NUnitTask -ThatFails -WhenJoinPathResolveFails -WithError $withError -ErrorAction SilentlyContinue
    }
}

Describe 'NUnit2.when running NUnit tests with coverage filters' {
    # Skip until we there is an OpenCover task and we can deprecate coverage in this task.
    It 'should pass coverage filters to OpenCover' -Skip {
        $coverageFilter = (
                        '-[NUnit2FailingTest]*',
                        '+[NUnit2PassingTest]*'
                        )
        Invoke-NUnitTask -WithRunningTests -CoverageFilter $coverageFilter
    }
}

Describe 'NUnit2.when including tests by category' {
    It 'should pass categories to NUnit' -Skip:$skip {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Include' = '"Category with Spaces 1,Category with Spaces 2"' }
        ThenTestsPassed 'HasCategory1','HasCategory2'
        ThenTestsNotRun 'ShouldPass'
    }
}

Describe 'NUnit2.when code coverage is disabled and using category filters with spaces' {
    It 'should pass categories to NUnit' {
        Init
        GivenCodeCoverageIsDisabled
        GivenPassingTests
        GivenInclude -Value 'Category with Spaces 1,Category With Spaces 1'
        GivenExclude -Value 'Category with Spaces,Another with spaces'
        GivenCodeCoverageIsDisabled
        WhenRunningTask
        ThenNoErrorShouldBeThrown
    }
}

Describe 'NUnit2.when excluding tests by category' {
    It 'should not run excluded tests' -Skip:$skip {
        Init
        GivenPassingTests
        GivenExclude '"Category with Spaces 1,Category with Spaces 2"'
        WhenRunningTask
        ThenTestsNotRun 'HasCategory1','HasCategory2'
        ThenTestsPassed 'ShouldPass'
    }
}

Describe 'NUnit2.when running with custom arguments' {
    It 'should pass arguments' -Skip:$skip {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
        ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
    }
}

Describe 'NUnit2.when running under a custom dotNET framework' {
    It 'should use custom framework' -Skip:$skip {
        Init
        GivenPassingTests
        WhenRunningTask @{ 'Framework' = 'net-4.5' }
        ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
    }
}

Describe 'NUnit2.when running with custom OpenCover arguments' {
    # Skip until we there is an OpenCover task and we can deprecate coverage in this task.
    It 'should pass custom OpenCover arguments' -Skip {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'OpenCoverArgument' = @( '-showunvisited' ) }
        ThenOutput -Contains '====Unvisited Classes===='
    }
}

Describe 'NUnit2.when running with custom ReportGenerator arguments' {
    # Skip until we there is an OpenCover task and we can deprecate coverage in this task.
    It 'should pass ReportGenerator arguments' -Skip {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'ReportGeneratorArgument' = @( '-reporttypes:Latex', '-verbosity:Info' ) }
        ThenOutput -Contains 'Initializing report builders for report types: Latex'
        ThenOutput -DoesNotContain 'Preprocessing report', 'Initiating parser for OpenCover'
    }
}

Describe 'NUnit2.when the Initialize Switch is active' {
    It 'should install dependencies' -Skip:$skip {
        Init
        GivenPassingTests
        WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
        ThenItInstalled 'Nunit.Runners' $latestNUnit2Version
        ThenItInstalled 'OpenCover' $latestOpenCoverVersion
        ThenItInstalled 'ReportGenerator' $latestReportGeneratorVersion
        ThenItShouldNotRunTests
    }
}

Describe 'NUnit2.when using custom tool versions' {
    It 'should use those tool versions' -Skip:$skip {
        Init
        GivenPassingTests
        GivenOpenCoverVersion '4.0.1229'
        GivenReportGeneratorVersion '2.5.11'
        GivenVersion '2.6.1'
        WhenRunningTask
        ThenItInstalled 'Nunit.Runners' '2.6.1'
        ThenItInstalled 'OpenCover' '4.0.1229'
        ThenItInstalled 'ReportGenerator' '2.5.11'
    }
}

Describe 'NUnit2.when initializing and no path is included' {
    It 'should fail' {
        Init
        GivenPassingTests
        GivenInvalidPath
        WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
        ThenItInstalled 'NUnit.Runners' $latestNUnit2Version
        ThenItInstalled 'OpenCover' $latestOpenCoverVersion
        ThenItInstalled 'ReportGenerator' $latestReportGeneratorVersion
        ThenItShouldNotRunTests
        ThenErrorShouldNotBeThrown -ErrorMessage 'do not exist.'
    }
}

Describe 'NUnit2.when using version of NUnit that isn''t 2' {
    It 'should fail' {
        Init
        GivenPassingTests
        GivenVersion '3.7.0'
        WhenRunningTask
        ThenItShouldNotRunTests
        ThenErrorIs 'isn''t\ a\ valid\ 2\.x\ version\ of\ NUnit'
    }
}
