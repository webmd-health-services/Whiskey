Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'

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

        [Version]
        $WithOpenCoverVersion = '4.6.519',

        [Version]
        $WithReportGeneratorVersion = '2.5.7',

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
        $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForDeveloper @inReleaseParam -ForOutputDirectory $outputDirectory
        $threwException = $false
        $Global:Error.Clear()

        if( $WithRunningTests )
        {
            $taskParameter = @{
                            Path = @(
                                        'NUnit2FailingTest\NUnit2FailingTest.sln',
                                        'NUnit2PassingTest\NUnit2PassingTest.sln'   
                                    )
                          }
            Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
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
                                            'NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
                                        )
                              }
        }        
        else
        {
            $taskParameter = @{
                                Path = @(
                                            'NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll',
                                            'NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
                                        )
                              }
        }

        $optionalParams = @{ }
        if( $WhenRunningClean )
        {
            $optionalParams['Clean'] = $True
            #check to be sure that we are only uninstalling the desired version of particular packages on clean
            Install-WhsCITool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -DownloadRoot $context.BuildRoot
        }
        if( $WithDisabledCodeCoverage )
        {
            $optionalParams['DisableCodeCoverage'] = $True
        }


        $Global:Error.Clear()
        try
        {
            Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $taskParameter @optionalParams -ErrorAction SilentlyContinue
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
            $openCoverPath = Join-Path -Path $packagesPath -ChildPath ('OpenCover.{0}' -f $WithOpenCoverVersion)
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
                $openCoverPath | should not exist
            }
            It 'should uninstall ReportGenerator' {
                $reportGeneratorPath | should not exist
            }
            Uninstall-WhsCITool -NuGetPackageName 'NUnit.Runners' -Version '2.6.3' -BuildRoot $context.BuildRoot
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
                (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\packages\NUnit.Runners.2.6.4') | Should Exist
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

        Remove-Item -Path $context.OutputDirectory -Recurse -Force        
    }
}

Describe 'Invoke-WhsCINUnit2Task.when the Clean Switch is active' {
    Invoke-NUnitTask -WhenRunningClean
}

Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' { 
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { $false }
    Invoke-NUnitTask -WithRunningTests -InReleaseMode
}

Describe 'Invoke-WhsCINUnit2Task when running failing NUnit2 tests' {
    $withError = [regex]::Escape('NUnit2 tests failed')
    Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError 
}

Describe 'Invoke-WhsCINUnit2Task when Install-WhsCITool fails' {
    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -MockWith { return $false }
    Invoke-NUnitTask -ThatFails
}

Describe 'Invoke-WhsCINUnit2Task when Path Parameter is not included' {
    $withError = [regex]::Escape('Element ''Path'' is mandatory')
    Invoke-NUnitTask -ThatFails -WithNoPath -WithError $withError
}

Describe 'Invoke-WhsCINUnit2Task when Path Parameter is invalid' {
    $withError = [regex]::Escape('does not exist.')
    Invoke-NUnitTask -ThatFails -WithInvalidPath -WithError $withError
}

Describe 'Invoke-WhsCINUnit2Task when NUnit Console Path is invalid and Join-Path -resolve fails' {
    Mock -CommandName 'Join-Path' -ModuleName 'WhsCI' -MockWith { Write-Error 'Path does not exist!' } -ParameterFilter { $ChildPath -eq 'nunit-console.exe' }
    $withError = [regex]::Escape('was installed, but couldn''t find nunit-console.exe')
    Invoke-NUnitTask -ThatFails -WhenJoinPathResolveFails -WithError $withError     
}

Describe 'Invoke-WhsCINUnit2Task when running NUnit tests with disabled code coverage' { 
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { $false }
    Invoke-NUnitTask -WithRunningTests -InReleaseMode -WithDisabledCodeCoverage
}

$solutionToBuild = $null
$assemblyToTest = $null
$buildScript = $null
$output = $null
$context = $null
$threwException = $false
$thrownError = $null

function GivenPassingTests
{
    $script:solutionToBuild = 'NUnit2PassingTest.sln'
    $script:assemblyToTest = 'NUnit2PassingTest.dll'
    $script:buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\whsbuild.yml'
}

function WhenRunningTask
{
    param(
        [hashtable]
        $WithParameters = @{ }
    )
    $outputDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $script:context = New-WhsCITestContext -ForDeveloper -BuildConfiguration 'Release' -ConfigurationPath $buildScript -ForOutputDirectory $outputDirectory

    Get-ChildItem -Path $context.OutputDirectory | Remove-Item -Recurse -Force

    Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter @{ 'Path' = $solutionToBuild }

    try
    {
        $WithParameters['Path'] = 'bin\Release\{0}' -f $assemblyToTest
        $script:output = Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $WithParameters | ForEach-Object { Write-Verbose -Message $_ ; $_ }
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

Describe 'Invoke-WhsCINUnit2Task.when including tests by category' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Include' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsPassed 'HasCategory1','HasCategory2'
    ThenTestsNotRun 'ShouldPass'
}

Describe 'Invoke-WhsCINUnit2Task.when excluding tests by category' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Exclude' = 'Category with Spaces 1','Category with Spaces 2' }
    ThenTestsNotRun 'HasCategory1','HasCategory2'
    ThenTestsPassed 'ShouldPass'
}

Describe 'Invoke-WhsCINUnit2Task.when running with custom arguments' {
    GivenPassingTests
    WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
    ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
}

Describe 'Invoke-WhsCINUnit2Task.when running under a custom dotNET framework' {
    GivenPassingTests
    WhenRunningTask @{ 'Framework' = 'net-4.5' }
    ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
}
