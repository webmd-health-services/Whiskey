
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$modulesDirectoryName = 'PSModules'

$context = $null
$pesterPath = $null
$version = $null
$taskParameter = @{}
$failed = $false

# So we can mock Whiskey's private function.
function Publish-WhiskeyPesterTestResult
{
}

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

    $manifest = Test-ModuleManifest -Path $pesterPath
    $manifest.Version.ToString() | Should -BeLike $ExpectedVersion

    $script:failed | Should -BeFalse

    $pesterPath | Should Exist
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
    $script:failed | Should -BeFalse

    Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -Times 1 -ModuleName 'Whiskey'
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
        $testReports | Should Not BeNullOrEmpty
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
    $total | Should -Be $expectedTotal

    $failed | Should -Be $FailureCount

    $passed | Should -Be $PassingCount

    foreach( $reportPath in $testReports )
    {
        $reportPath = $reportPath.FullName
        Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey' -ParameterFilter { 
            $DebugPreference = 'Continue'
            Write-Debug ('{0}  -eq  {1}' -f $Path,$reportPath) 
            $Path -eq $reportPath 
        }
    }
}
function ThenTestShouldFail
{
    param(
        [string]
        $failureMessage
    )
    $Script:failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $failureMessage} | Should -Not -BeNullOrEmpty
}

function ThenNoPesterTestFileShouldExist {
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    $testReports | Should -BeNullOrEmpty

}

function ThenTestShouldCreateMultipleReportFiles
{
    Get-ChildItem -Path (Join-Path -Path $context.OutputDirectory -ChildPath 'pester+*.xml') |
        Measure-Object |
        Select-Object -ExpandProperty 'Count' |
        Should -Be 2
}

if( -not $IsWindows )
{
    Describe 'Pester3.when running on non-Windows platform' {
        It 'should fail' {
            GivenTestContext
            GivenPesterPath -pesterPath 'PassingTests'
            GivenVersion '3.4.3'
            WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
            ThenTestShouldFail -failureMessage 'Windows\ platform'
        }
    }

    return
}

Describe 'Pester3.when running passing Pester tests' {
    It 'should not fail' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked 
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 4
        ThenPesterShouldBeInstalled '3.4.3'
    }
}

Describe 'Pester3.when running failing Pester tests' {
    It 'should fail' {
        GivenTestContext
        GivenPesterPath -pesterPath 'FailingTests'
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 0
        ThenTestShouldFail -failureMessage 'Pester tests failed'
    }
}

Describe 'Pester3.when running multiple test scripts' {
    It 'should run them all' {
        GivenTestContext
        GivenPesterPath 'FailingTests','PassingTests'
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 4 -PassingCount 4
    }
}

Describe 'Pester3.when run multiple times in the same build' {
    It 'should output separate reports for each run' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'  
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 8 -FailureCount 0
        ThenPesterShouldBeInstalled '3.4.3'
        ThenTestShouldCreateMultipleReportFiles
    }
}

Describe 'Pester3.when missing Path Configuration' {
    It 'should fail' {
        GivenTestContext
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'Element ''Path'' is mandatory.'
    }
}

Describe 'Pester3.when missing Version configuration' {
    It 'should install latest version of Pester 3' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 4 -FailureCount 0
        ThenPesterShouldBeInstalled '3.4.6'
    }
}

Describe 'Pester3.when a task path is absolute' {
    It 'should fail' {
        GivenTestContext
        GivenPesterPath -pesterPath 'C:\FubarSnafu'
        GivenVersion '3.4.3'
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'absolute'
    }
}

Describe 'Pester3.when running passing Pester tests with Clean Switch the tests don''t run' {
    It 'should remove Pester and not run any tests' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'
        GivenVersion '3.4.3'
        GivenWithCleanFlag
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
        ThenPesterShouldBeUninstalled
    }
}

Describe 'Pester3.when running passing Pester tests with initialization switch the tests don''t run' {
    It 'should install Pester but not run any tests' {
        GivenTestContext
        GivenPesterPath -pesterPath 'PassingTests'
        GivenVersion '3.4.3'
        GivenWithInitilizeFlag
        WhenPesterTaskIsInvoked
        ThenNoPesterTestFileShouldExist 
        ThenPesterShouldBeInstalled '3.4.3'
    }
}

