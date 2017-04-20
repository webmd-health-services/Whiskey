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
        $WhenRunningClean
    )
    Process
    {
        $inReleaseParam = @{ }
        if ( $InReleaseMode )
        {
            $inReleaseParam['InReleaseMode'] = $True
        }
        $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForDeveloper @inReleaseParam
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
        if( $WhenRunningClean )
        {
            It 'should not throw an exception' {
                $threwException | Should be $False
            }
            It 'should not exit with error' {
                $Global:Error | Should beNullorEmpty
            } 
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
        }
        else
        {
            Assert-NUnitTestsNotRun -ReportPath $reportPath
        }

        Remove-Item -Path $context.OutputDirectory -Recurse -Force        
    }
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

Describe 'Invoke-WhsCINUnit2Task.when the Clean Switch is active' {
    Invoke-NUnitTask -WhenRunningClean
}

$solutionToBuild = $null
$assemblyToTest = $null
$buildScript = $null
$output = $null
$context = $null

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

    $script:context = New-WhsCITestContext -ForDeveloper -BuildConfiguration 'Release' -ConfigurationPath $buildScript

    Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter @{ 'Path' = $solutionToBuild }

    $WithParameters['Path'] = 'bin\Release\{0}' -f $assemblyToTest
    $script:output = Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $WithParameters
    $script:output | Write-Verbose -Verbose
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

function ThenTestsNotRun
{
    param(
        [string[]]
        $TestName
    )

    foreach( $name in $TestName )
    {
        It ('{0} should not run' -f $name) {
            Get-TestCaseResult -TestName $name | Should BeNullOrEmpty
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
            $result.GetAttribute('result') | Should Be 'Success'
        }
    }
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