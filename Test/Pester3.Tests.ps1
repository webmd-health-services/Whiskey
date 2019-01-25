
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Publish-WhiskeyPesterTestResult.ps1' -Resolve)

$modulesDirectoryName = 'PSModules'

$context = $null
$pesterPath = $null
$version = $null
$taskParameter = @{}
$failed = $false

function GivenTestContext
{
    $script:pesterPath = $null
    $script:version = $null
    $script:failed = $false
    $script:taskParameter = @{}
    $Global:Error.Clear()
    $script:context = New-WhiskeyPesterTestContext

    $pesterDirectoryName = '{0}\Pester' -f $modulesDirectoryName
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = '{0}\Pester\{1}' -f $modulesDirectoryName,$Version
    }
    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    if(Test-Path $pesterPAth)
    {
        Remove-item $pesterPath -Recurse -Force
    }
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
        $script:context = New-WhiskeyTestContext -ForTaskName 'Pester3' -ForOutputDirectory $outputRoot -ForBuildRoot $buildRoot -ForDeveloper
        return $context
    }
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
    $Script:taskparameter['version'] = '3.0.0'
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
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester3'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenPesterShouldBeInstalled
{
    param(
        [string]
        $ExpectedVersion
    )

    $pesterDirectoryName = '{0}\Pester' -f $modulesDirectoryName
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = '{0}\Pester\{1}' -f $modulesDirectoryName,$ExpectedVersion
    }
    $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName
    $pesterPath = Join-Path -Path $pesterPath -ChildPath 'Pester.psd1'

    It ('should install Pester {0}' -f $ExpectedVersion) {
        $manifest = Test-ModuleManifest -Path $pesterPath
        $manifest.Version.ToString() | Should -BeLike $ExpectedVersion
    }

    It 'should pass' {
        $script:failed | Should Be $false
    }
    It 'Should pass the build root to the Install tool' {
        $pesterPath | Should Exist
    }
}

function ThenPesterShouldBeUninstalled {
    if( -not $script:Taskparameter['Version'] )
    {
        $latestPester = ( Find-Module -Name 'Pester' -AllVersions | Where-Object { $_.Version -like '3.*' } ) 
        $latestPester = $latestPester | Sort-Object -Property Version -Descending | Select-Object -First 1
        $version = $latestPester.Version 
        $script:Taskparameter['Version'] = '{0}.{1}.{2}' -f ($Version.major, $Version.minor, $Version.build)
    }
    else
    {
        $script:Taskparameter['Version'] = $script:Taskparameter['Version'] | ConvertTo-WhiskeySemanticVersion
        $script:Taskparameter['Version'] = '{0}.{1}.{2}' -f ($script:Taskparameter['Version'].major, $script:Taskparameter['Version'].minor, $script:Taskparameter['Version'].patch)
    }
    $pesterDirectoryName = '{0}\Pester' -f $modulesDirectoryName
    if( $PSVersionTable.PSVersion.Major -ge 5 )
    {
        $pesterDirectoryName = '{0}\Pester\{1}' -f $modulesDirectoryName,$Version
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
            $reportPath = $reportPath.FullName
            Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey' -ParameterFilter { 
                $DebugPreference = 'Continue'
                Write-Debug ('{0}  -eq  {1}' -f $Path,$reportPath) 
                $Path -eq $reportPath 
            }
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

function ThenNoPesterTestFileShouldExist {
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    it 'should not have created any test reports' {
        $testReports | should BeNullOrEmpty
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

if( -not $IsWindows )
{
    Describe 'Pester3.when running on non-Windows platform' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenTestShouldFail -failureMessage 'Windows\ platform'
    }

    return
}

Describe 'Pester3.when running passing Pester tests' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked 
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 4
    ThenPesterShouldBeInstalled '3.4.3'
}

Describe 'Pester3.when running failing Pester tests' {
    GivenTestContext
    GivenPesterPath -pesterPath 'FailingTests'
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 0
    ThenTestShouldFail -failureMessage 'Pester tests failed'
}

Describe 'Pester3.when running multiple test scripts' {
    GivenTestContext
    GivenPesterPath 'FailingTests','PassingTests'
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 4
}

Describe 'Pester3.when run multiple times in the same build' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'  
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 8 -FailureCount 0
    ThenPesterShouldBeInstalled '3.4.3'
    ThenTestShouldCreateMultipleReportFiles
}

Describe 'Pester3.when missing Path Configuration' {
    GivenTestContext
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'Element ''Path'' is mandatory.'
}

Describe 'Pester3.when missing Version configuration' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -PassingCount 4 -FailureCount 0
    ThenPesterShouldBeInstalled '3.4.6'
}

Describe 'Pester3.when a task path is absolute' {
    GivenTestContext
    GivenPesterPath -pesterPath 'C:\FubarSnafu'
    GivenVersion '3.4.3'
    WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
    ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
    ThenTestShouldFail -failureMessage 'absolute'
}

Describe 'Pester3.when running passing Pester tests with Clean Switch the tests dont run' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '3.4.3'
    GivenWithCleanFlag
    WhenPesterTaskIsInvoked
    ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
    ThenPesterShouldBeUninstalled
}

Describe 'Pester3.when running passing Pester tests with initialization switch the tests dont run' {
    GivenTestContext
    GivenPesterPath -pesterPath 'PassingTests'
    GivenVersion '3.4.3'
    GivenWithInitilizeFlag
    WhenPesterTaskIsInvoked
    ThenNoPesterTestFileShouldExist 
    ThenPesterShouldBeInstalled '3.4.3'
}

