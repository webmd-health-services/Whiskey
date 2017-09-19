Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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
        $InReleaseMode,

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

        [Switch]
        $WithDisabledCodeCoverage,

        [String[]]
        $CoverageFilter
    )
    Process
    {
        $inReleaseParam = @{ }
        if ( $InReleaseMode )
        {
            $inReleaseParam['InReleaseMode'] = $True
        }
        $outputDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
        $context = New-WhiskeyTestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForDeveloper @inReleaseParam -ForOutputDirectory $outputDirectory
        $configuration = Get-WhiskeyMSBuildConfiguration -Context $context
        $threwException = $false
        $Global:Error.Clear()

        $ReportGeneratorVersion = '2.5.11'

        if( $WithRunningTests )
        {
            $taskParameter = @{
                            Path = @(
                                        'NUnit2FailingTest\NUnit2FailingTest.sln',
                                        'NUnit2PassingTest\NUnit2PassingTest.sln'   
                                    )
                          }
            Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'MSBuild'
        }
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
                                            ('NUnit2FailingTest\bin\{0}\NUnit2FailingTest.dll' -f $configuration)
                                        )
                              }
        }        
        else
        {
            $taskParameter = @{
                                Path = @(
                                            ('NUnit2PassingTest\bin\{0}\NUnit2PassingTest.dll' -f $configuration),
                                            ('NUnit2FailingTest\bin\{0}\NUnit2FailingTest.dll' -f $configuration)
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
        $taskParameter.Add('ReportGeneratorVersion', $latestReportGeneratorVersion)

        if( $WhenRunningClean )
        {
            $context.RunMode = 'Clean'
            #check to be sure that we are only uninstalling the desired version of particular packages on clean
            Install-WhiskeyTool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -DownloadRoot $context.BuildRoot
        }

        $Global:Error.Clear()
        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NUnit2' -ErrorAction SilentlyContinue
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
            $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath 'ReportGenerator.*'
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

Describe 'Invoke-WhiskeyNUnit2Task.when the Clean Switch is active' {
    Invoke-NUnitTask -WhenRunningClean
}

Describe 'Invoke-WhiskeyNUnit2Task when running NUnit tests' { 
    Invoke-NUnitTask -WithRunningTests -InReleaseMode
}

Describe 'Invoke-WhiskeyNUnit2Task when running failing NUnit2 tests' {
    $withError = [regex]::Escape('NUnit2 tests failed')
    Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError 
}

Describe 'Invoke-WhiskeyNUnit2Task when Install-WhiskeyTool fails' {
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith { return $false }
    Invoke-NUnitTask -ThatFails
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
    Invoke-NUnitTask -ThatFails -WhenJoinPathResolveFails -WithError $withError     
}

Describe 'Invoke-WhiskeyNUnit2Task when running NUnit tests with disabled code coverage' { 
    Invoke-NUnitTask -WithRunningTests -InReleaseMode -WithDisabledCodeCoverage
}

Describe 'Invoke-WhiskeyNUnit2Task when running NUnit tests with coverage filters' { 
    $coverageFilter = (
                    '-[NUnit2FailingTest]*',
                    '+[NUnit2PassingTest]*'
                    )
    Invoke-NUnitTask -WithRunningTests -InReleaseMode -CoverageFilter $coverageFilter
}

$solutionToBuild = $null
$assemblyToTest = $null
$buildScript = $null
$output = $null
$context = $null
$threwException = $false
$thrownError = $null
$taskParameter = $null
function GivenPassingTests
{
    $script:solutionToBuild = 'NUnit2PassingTest.sln'
    $script:assemblyToTest = 'NUnit2PassingTest.dll'
    $script:buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\whiskey.yml'
    $script:taskParameter = @{ 'Path' = $script:solutionToBuild }
}
function GivenInvalidPath
{
    $script:assemblyToTest = 'I/do/not/exist'
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
    $outputDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $script:context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath $buildScript -ForOutputDirectory $outputDirectory -ForBuildRoot ($buildScript | Split-Path)

    Get-ChildItem -Path $context.OutputDirectory | Remove-Item -Recurse -Force
    Get-ChildItem -Path $context.BuildRoot -Include 'bin','obj' -Directory -Recurse | Remove-Item -Recurse -Force
    
    $configuration = Get-WhiskeyMSBuildConfiguration -Context $context

    Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'MSBuild'

    # Make sure there are spaces in the path so that we test things get escaped properly.
    Get-ChildItem -Path $context.BuildRoot -Filter $configuration -Directory -Recurse |
        Rename-Item -NewName ('{0} Mode' -f $configuration)
    if( $WhenRunningInitialize )
    {
        $context.RunMode = 'initialize'
    }
    try
    {
        $WithParameters['Path'] = 'bin\{0} Mode\{1}' -f $configuration,$assemblyToTest
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
function ThenItInstalledNunit {
    $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
    $nunitPath = Join-Path -Path $packagesPath -ChildPath 'NUnit.Runners.2.6.4'
    It 'should have installed the expected version of Nunit.Runners' {
        $nunitPath | should exist
    }
    Uninstall-WhiskeyTool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -BuildRoot $context.BuildRoot
}
function ThenItInstalledOpenCover {
    param (
        [Version]
        $WithOpenCoverVersion = '4.6.519'
    )

    $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
    $openCoverPackagePath = Join-Path -Path $packagesPath -ChildPath ('OpenCover.{0}' -f $WithOpenCoverVersion)

    It 'should have installed OpenCover' {
        $openCoverPackagePath | should exist
    }
}

function ThenItInstalledReportGenerator {

    $packagesPath = Join-Path -Path $context.BuildRoot -ChildPath 'Packages'
    $reportGeneratorPath = Join-Path -Path $packagesPath -ChildPath 'ReportGenerator.*'
    
    It 'should have installed ReportGenerator' {
        $reportGeneratorPath | should exist
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
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Include' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsPassed 'HasCategory1','HasCategory2'
    ThenTestsNotRun 'ShouldPass'
}

Describe 'Invoke-WhiskeyNUnit2Task.when excluding tests by category' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Exclude' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsNotRun 'HasCategory1','HasCategory2'
    ThenTestsPassed 'ShouldPass'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom arguments' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
    ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running under a custom dotNET framework' {
    GivenPassingTests
    WhenRunningTask @{ 'Framework' = 'net-4.5' }
    ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom OpenCover arguments' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'OpenCoverArgument' = @( '-showunvisited' ) }
    ThenOutput -Contains '====Unvisited Classes===='
}

Describe 'Invoke-WhiskeyNUnit2Task.when running with custom ReportGenerator arguments' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'ReportGeneratorArgument' = @( '-reporttypes:Latex', '-verbosity:Info' ) }
    ThenOutput -Contains 'Initializing report builders for report types: Latex'
    ThenOutput -DoesNotContain 'Preprocessing report', 'Initiating parser for OpenCover'
}

Describe 'Invoke-WhiskeyNUnit2Task.when the Initialize Switch is active' {
    GivenPassingTests
    WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
    ThenItInstalledNunit
    ThenItInstalledOpenCover
    ThenItInstalledReportGenerator
    ThenItShouldNotRunTests
}

Describe 'Invoke-WhiskeyNUnit2Task.when the Initialize Switch is active and No path is included' {
    GivenPassingTests
    GivenInvalidPath
    WhenRunningTask -WhenRunningInitialize -WithParameters @{ }
    ThenItInstalledNunit
    ThenItInstalledOpenCover
    ThenItInstalledReportGenerator
    ThenItShouldNotRunTests
    ThenErrorShouldNotBeThrown -ErrorMessage 'does not exist.'
}
