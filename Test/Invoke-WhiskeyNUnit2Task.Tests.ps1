Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\NuGet.exe' -Resolve

$latestNUnit2Version = '2.6.4'
$latestOpenCoverVersion,$latestReportGeneratorVersion = & {
                                                                & $nugetPath list packageid:OpenCover
                                                                & $nugetPath list packageid:ReportGenerator
                                                        } |
                                                        Where-Object { $_ -match ' (\d+\.\d+\.\d+.*)' } |
                                                        ForEach-Object { $Matches[1] }

$packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
Remove-Item -Path $packagesRoot -Recurse -Force -ErrorAction Ignore
& $nugetPath install OpenCover -OutputDirectory $packagesRoot
& $nugetPath install ReportGenerator -OutputDirectory $packagesRoot
& $nugetPath install NUnit.Runners -Version $latestNUnit2Version -OutputDirectory $packagesRoot

$taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit2.yml')
Invoke-WhiskeyBuild -Context $taskContext

function Assert-NUnitTestsRun
{
    param(
        [string]
        $ReportPath
    )
    It 'should run NUnit tests' {
        $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml' | Should not BeNullOrEmpty
    }   
}

function Assert-NUnitTestsNotRun
{
    param(
        [string]
        $ReportPath
    )
    It 'should not run NUnit tests' {
        $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}

function Assert-OpenCoverRuns
{
    param(
        [String]
        $OpenCoverDirectoryPath
    )
    $openCoverFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'openCover.xml'
    $reportGeneratorFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'index.htm'
    It 'should run OpenCover' {
        $openCoverFilePath | Should exist
    }
    It 'should run ReportGenerator' {
        $reportGeneratorFilePath | Should exist
    }
}

function Assert-OpenCoverNotRun
{
    param(
        [String]
        $OpenCoverDirectoryPath
    )
    $openCoverFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'openCover.xml'
    $reportGeneratorFilePath = Join-Path -Path $OpenCoverDirectoryPath -ChildPath 'index.htm'
    It 'should not run OpenCover' {
        $openCoverFilePath | Should not exist
    }
    It 'should not run ReportGenerator' {
        $reportGeneratorFilePath | Should not exist
    }
}

function Invoke-NUnitTask 
{

    [CmdletBinding()]
    param(
        [Switch]
        $ThatFails,

        [Switch]
        $WithNoPath,

        [Switch]
        $WithInvalidPath,

        [Switch]
        $WhenJoinPathResolveFails,

        [switch]
        $WithFailingTests,

        [switch]
        $WithRunningTests,

        [String]
        $WithError,

        [Switch]
        $WhenRunningClean,

        [Switch]
        $WhenRunningInitialize,

        [Version]
        $WithOpenCoverVersion = '4.6.519',

        [Version]
        $WithReportGeneratorVersion,

        [Switch]
        $WithDisabledCodeCoverage,

        [String[]]
        $CoverageFilter,

        [ScriptBlock]
        $MockInstallWhiskeyToolWith
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
        $taskParameter.Add('OpenCoverVersion', $WithOpenCoverVersion)
        if( $WithReportGeneratorVersion )
        {
            $taskParameter.Add('ReportGeneratorVersion', $WithReportGeneratorVersion)
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
                It 'should write an error'{
                    $Global:Error[0] | Should Match ( $WithError )
                }
            }
            else
            {
                It 'should write an error'{
                    $Global:Error | Should Match ( $WithError )
                }
            }
        }

        $ReportPath = Join-Path -Path $context.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $context.TaskIndex)
        $openCoverPath = Join-Path -Path $context.OutputDirectory -ChildPath 'OpenCover'
        if( $WhenRunningClean )
        {
            $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
            $nunitPath = Join-Path -Path $packagesPath -ChildPath 'NUnit.Runners.2.6.4'
            $oldNUnitPath = Join-Path -Path $packagesPath -ChildPath 'NUnit.Runners.2.6.3'
            $openCoverPackagePath = Join-Path -Path $packagesPath -ChildPath ('OpenCover.{0}' -f $WithOpenCoverVersion)
            if( -not $WithReportGeneratorVersion )
            {
                $WithReportGeneratorVersion = $latestReportGeneratorVersion
            }

            $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath ('ReportGenerator.{0}' -f $WithReportGeneratorVersion)
            It 'should not throw an exception' {
                $threwException | Should be $False
            }
            It 'should not exit with error' {
                $Global:Error | Should beNullorEmpty
            } 
            It 'should uninstall the expected version of Nunit.Runners' {
                $nunitPath | should not exist
            }
            It 'should not uninstall other versions of NUnit.Runners' {
                $oldNUnitPath | should exist
            }
            It 'should uninstall OpenCover' {
                $openCoverPackagePath | should not exist
            }
            It 'should uninstall ReportGenerator' {
                $reportGeneratorPath | should not exist
            }
            Uninstall-WhiskeyTool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -BuildRoot $context.BuildRoot
        }
        elseif( $ThatFails )
        {            
            It 'should throw an exception'{
                $threwException | Should Be $True
            }
        }
        else
        {
            It 'should download NUnit.Runners' {
                (Join-Path -Path $context.BuildRoot -ChildPath 'packages\NUnit.Runners.2.6.4') | Should Exist
            }
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
            It ('should run allowed assemblies to pass through the OpenCover coverage filter') {
                $plusFilterPath | should exist
            }
            It ('should not run assemblies disabled by the OpenCover coverage filter') {
                $minusFilterPath | should not exist
            }
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

Describe 'Invoke-WhiskeyNUnit2Task.when the Clean Switch is active' {
    GivenNuGetPackageInstalled 'NUnit.Runners' -AtVersion '2.6.3'
    Invoke-NUnitTask -WhenRunningClean
}

Describe 'Invoke-WhiskeyNUnit2Task when running NUnit tests' { 
    Context 'no code coverage' {
        Invoke-NUnitTask -WithRunningTests -WithDisabledCodeCoverage
    }
    Context 'code coverage' {
        Invoke-NUnitTask -WithRunningTests
    }
}

Describe 'Invoke-WhiskeyNUnit2Task when running failing NUnit2 tests' {
    $withError = [regex]::Escape('NUnit2 tests failed')
    Context 'no code coverage' {
        Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError -WithDisabledCodeCoverage
    }
    Context 'code coverage' {
        Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError
    }
}

Describe 'Invoke-WhiskeyNUnit2Task when Install-WhiskeyTool fails' {
    Invoke-NUnitTask -ThatFails -MockInstallWhiskeyToolWith { return $false }
}

Describe 'Invoke-WhiskeyNUnit2Task when Path Parameter is not included' {
    $withError = [regex]::Escape('Element ''Path'' is mandatory')
    Invoke-NUnitTask -ThatFails -WithNoPath -WithError $withError
}

Describe 'Invoke-WhiskeyNUnit2Task when Path Parameter is invalid' {
    $withError = [regex]::Escape('does not exist.')
    Invoke-NUnitTask -ThatFails -WithInvalidPath -WithError $withError
}

Describe 'Invoke-WhiskeyNUnit2Task when NUnit Console Path is invalid and Join-Path -resolve fails' {
    Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -MockWith { Write-Error 'Path does not exist!' } -ParameterFilter { $ChildPath -eq 'nunit-console.exe' }
    $withError = [regex]::Escape('was installed, but couldn''t find nunit-console.exe')
    Invoke-NUnitTask -ThatFails -WhenJoinPathResolveFails -WithError $withError -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhiskeyNUnit2Task when running NUnit tests with coverage filters' { 
    $coverageFilter = (
                    '-[NUnit2FailingTest]*',
                    '+[NUnit2PassingTest]*'
                    )
    Invoke-NUnitTask -WithRunningTests -CoverageFilter $coverageFilter
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

function Init
{
    $script:openCoverVersion = $null
    $script:reportGeneratorVersion = $null
    $script:nunitVersion = $null
    $script:enableCodeCoverage = $false

    robocopy $packagesRoot (Join-Path -Path $TestDrive.FullName -ChildPath 'packages')
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName

    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName
    Copy-Item -Path $packagesRoot -Destination $TestDrive.FullName -Recurse -ErrorAction Ignore
}

function WhenRunningTask
{
    param(
        [hashtable]
        $WithParameters = @{ },

        [Switch]
        $WhenRunningInitialize
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

        if( $nunitVersion )
        {
            $WithParameters['Version'] = $nunitVersion
        }
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameters -Name 'NUnit2' | ForEach-Object { Write-Verbose -Message $_ ; $_ }
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
        [string]
        $TestName
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
        [string[]]
        $Contains,

        [string[]]
        $DoesNotContain
    )

    foreach( $regex in $Contains )
    {
        It ('should contain ''{0}''' -f $regex) {
            $output -join [Environment]::NewLine | Should -Match $regex
        }
    }

    foreach( $regex in $DoesNotContain )
    {
        It ('should not contain ''{0}''' -f $regex) {
            $output | Should -Not -Match $regex
        }
    }
}

function ThenTestsNotRun
{
    param(
        [string[]]
        $TestName
    )

    foreach( $name in $TestName )
    {
        It ('{0} should not run' -f $name) {
            Get-TestCaseResult -TestName $name | Should -BeNullOrEmpty
        }
    }
}

function ThenTestsPassed
{
    param(
        [string[]]
        $TestName
    )

    foreach( $name in $TestName )
    {
        $result = Get-TestCaseResult -TestName $name
        It ('{0} test should pass' -f $name) {
            $result.GetAttribute('result') | ForEach-Object { $_ | Should -Be 'Success' }
        }
    }
    Assert-OpenCoverRuns -OpenCoverDirectoryPath (Join-Path -path $Script:context.OutputDirectory -ChildPath 'OpenCover')
}

function ThenItShouldNotRunTests {
    $ReportPath = Join-Path -Path $context.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $context.TaskIndex)

    It 'should not run NUnit tests' {
        $ReportPath | Split-Path | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }   
}

function ThenItInstalled {
    param (
        [string]
        $Name,

        [Version]
        $Version
    )

    $expectedVersion = $Version
    It ('should have installed {0} {1}' -f $Name,$Version) {
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { 
            $DebugPreference = 'Continue'
            Write-Debug -Message ('NuGetPackageName  expected  {0}' -f $Name)
            Write-Debug -Message ('                  actual    {0}' -f $NuGetPackageName)
            $NuGetPackageName -eq $Name 
        }
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Version -eq $ExpectedVersion }
    }
}

function ThenErrorIs {
    param(
        $Regex
    )
    It ('should write an error that matches /{0}/' -f $Regex){
        $Global:Error | Should -Match $Regex
    }
}

function ThenErrorShouldNotBeThrown {
    param(
        $ErrorMessage
    )
    It ('should Not write an error that matches {0}' -f $ErrorMessage){
        $Global:Error | Where-Object { $_ -match $ErrorMessage } | Should BeNullOrEmpty
    }
}

Describe 'Invoke-WhiskeyNUnit2Task.when including tests by category' {
    Init
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Include' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsPassed 'HasCategory1','HasCategory2'
    ThenTestsNotRun 'ShouldPass'
}

Describe 'Invoke-WhiskeyNUnit2Task.when excluding tests by category' {
    Init
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Exclude' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsNotRun 'HasCategory1','HasCategory2'
    ThenTestsPassed 'ShouldPass'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom arguments' {
    Init
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
    ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running under a custom dotNET framework' {
    Init
    GivenPassingTests
    WhenRunningTask @{ 'Framework' = 'net-4.5' }
    ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom OpenCover arguments' {
    Init
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'OpenCoverArgument' = @( '-showunvisited' ) }
    ThenOutput -Contains '====Unvisited Classes===='
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom ReportGenerator arguments' {
    Init
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'ReportGeneratorArgument' = @( '-reporttypes:Latex', '-verbosity:Info' ) }
    ThenOutput -Contains 'Initializing report builders for report types: Latex'
    ThenOutput -DoesNotContain 'Preprocessing report', 'Initiating parser for OpenCover'
}

Describe 'Invoke-WhiskeyNUnit2Task.when the Initialize Switch is active' {
    Init
    GivenPassingTests
    WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
    ThenItInstalled 'Nunit.Runners' $latestNUnit2Version
    ThenItInstalled 'OpenCover' $latestOpenCoverVersion
    ThenItInstalled 'ReportGenerator' $latestReportGeneratorVersion
    ThenItShouldNotRunTests
}

Describe 'Invoke-WhiskeyNUnit2Task.when using custom tool versions' {
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

Describe 'Invoke-WhiskeyNUnit2Task.when the Initialize Switch is active and No path is included' {
    Init
    GivenPassingTests
    GivenInvalidPath
    WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
    ThenItInstalled 'NUnit.Runners' $latestNUnit2Version
    ThenItInstalled 'OpenCover' $latestOpenCoverVersion
    ThenItInstalled 'ReportGenerator' $latestReportGeneratorVersion
    ThenItShouldNotRunTests
    ThenErrorShouldNotBeThrown -ErrorMessage 'does not exist.'
}

Describe 'Invoke-WhiskeyNUnit2Task.when using version of NUnit that isn''t 2' {
    Init
    GivenPassingTests
    GivenVersion '3.7.0'
    WhenRunningTask
    ThenItShouldNotRunTests
    ThenErrorIs 'isn''t\ a\ valid\ 2\.x\ version\ of\ NUnit'
}