
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$version = $null
$taskParameter = @{}
$failed = $false
$output = $null

function GivenDescribeDurationReportCount
{
    param(
        $Count
    )

    $taskParameter['DescribeDurationReportCount'] = $Count
}

function GivenItDurationReportCount
{
    param(
        $Count
    )

    $taskParameter['ItDurationReportCount'] = $Count
}

function Init
{
    $script:taskParameter = @{}
    $script:version = $null
    $script:failed = $false
    $script:taskParameter = @{}
    $Global:Error.Clear()

    $script:testRoot = New-WhiskeyTestRoot

    $script:context = New-WhiskeyTestContext -ForTaskName 'Pester4' `
                                             -ForDeveloper `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'Pester'

    $pesterModuleRoot = Join-Path -Path $testRoot -ChildPath ('{0}\Pester' -f $TestPSModulesDirectoryName)
    Get-ChildItem -Path $pesterModuleRoot -ErrorAction Ignore | 
        Where-Object { $_.Name -notlike '4.*' } |
        Remove-Item -Recurse -Force

}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function GivenExclude
{
    param(
        $Exclude
    )

    $taskParameter['Exclude'] = $Exclude
}

function GivenVersion
{
    param(
        [String]$Version
    )
    $Script:taskParameter['Version'] = $Version
}

function GivenInvalidVersion
{
    $Script:taskParameter['Version'] = '4.0.0'
    Mock -CommandName 'Test-Path' `
        -ModuleName 'Whiskey' `
        -MockWith { return $False }`
        -ParameterFilter { $Path -eq $context.BuildRoot }
}

function GivenTestFile
{
    param(
        [String]$Path,
        [String]$Content
    )

    $taskParameter['Path'] = & {
        if( $taskParameter.ContainsKey('Path') )
        {
            $taskParameter['Path']
        }
        $Path 
    }

    if( -not [IO.Path]::IsPathRooted($Path) )
    {
        $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $Path)
    }
}

function WhenPesterTaskIsInvoked
{
    [CmdletBinding()]
    param(
        [switch]$WithClean,

        [switch]$NoJob,

        [hashtable]$WithArgument = @{ }
    )

    $failed = $false
    $Global:Error.Clear()

    Mock -CommandName 'Publish-WhiskeyPesterTestResult' -ModuleName 'Whiskey'

    if( $NoJob )
    {
        $taskParameter['NoJob'] = 'true'
    }

    $WithArgument['Show'] = 'None'
    $taskParameter['Argument'] = $WithArgument

    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester4'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function Get-OutputReportRowCount
{
    param(
        $Regex
    )

    $report = $output | Out-String
    $report = $report -split ([regex]::Escape([Environment]::Newline))
    $reportStarted = $false
    $rowCount = 0
    for( $idx = 0; $idx -lt $report.Count; ++$idx )
    {
        if( $reportStarted )
        {
            if( -not $report[$idx] )
            {
                break
            }
            $rowCount++
            continue
        }

        if( $report[$idx] -match $Regex )
        {
            $idx++
            $reportStarted = $true
        }
    }
    return $rowCount
}

function ThenDescribeDurationReportHasRows
{
    param(
        $Count
    )

    Get-OutputReportRowCount -Regex '\bDescribe\b +\bDuration\b' | Should -Be $Count
}

function ThenItDurationReportHasRows
{
    param(
        $Count
    )

    Get-OutputReportRowCount -Regex '\bDescribe\b +\bName\b +\bTime\b' | Should -Be $Count
}

function ThenPesterShouldHaveRun
{
    param(
        [Parameter(Mandatory)]
        [int]$FailureCount,
            
        [Parameter(Mandatory)]
        [int]$PassingCount,

        [Switch]$AsJUnitXml,

        [String]$ResultFileName = 'pester+*.xml'
    )

    $reportsIn =  $context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter $ResultFileName

    #check to see if we were supposed to run any tests.
    if( ($FailureCount + $PassingCount) -gt 0 )
    {
        $testReports | Should -Not -BeNullOrEmpty
    }

    $total = 0
    $failed = 0
    $passed = 0
    foreach( $testReport in $testReports )
    {
        $xml = [xml](Get-Content -Path $testReport.FullName -Raw)
        $totalAttrName = 'total'
        if( $AsJUnitXml )
        {
            $totalAttrName = 'tests'
        }
        $thisTotal = [int]($xml.DocumentElement.$totalAttrName)
        $thisFailed = [int]($xml.DocumentElement.'failures')
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
        Write-WhiskeyDebug -Context $context ('ReportsIn:  {0}' -f $ReportsIn)
        Write-WhiskeyDebug -Context $context ('reportPath: {0}' -f $reportPath)
        $reportPath = Join-Path -Path $ReportsIn -ChildPath $reportPath.Name
        Write-WhiskeyDebug -Context $context ('reportPath: {0}' -f $reportPath)
        Assert-MockCalled -CommandName 'Publish-WhiskeyPesterTestResult' `
                          -ModuleName 'Whiskey' `
                          -ParameterFilter { 
                                if( -not [IO.Path]::IsPathRooted($Path) )
                                {
                                    $Path = Join-Path -Path $testRoot -ChildPath $Path
                                }
                                Write-WhiskeyDebug ('{0}  -eq  {1}' -f $Path,$reportPath) 
                                $result = $Path -eq $reportPath 
                                Write-WhiskeyDebug ('  {0}' -f $result) 
                                return $result
                          }
    }
}

function ThenTestShouldFail
{
    param(
        [String]$failureMessage
    )
    $Script:failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $failureMessage} | Should -Not -BeNullOrEmpty
}

function ThenNoPesterTestFileShouldExist 
{
    $reportsIn =  $script:context.outputDirectory
    $testReports = Get-ChildItem -Path $reportsIn -Filter 'pester-*.xml'
    write-host $testReports
    $testReports | Should -BeNullOrEmpty
}

function ThenNoDurationReportPresent
{
    $output | Out-String | Should -Not -Match '\bDescribe\b( +\bName\b)? +\b(Duration|Time)\b'
}

function ThenTestShouldCreateMultipleReportFiles
{
    Get-ChildItem -Path (Join-Path -Path $context.OutputDirectory -ChildPath 'pester+*.xml') |
        Measure-Object |
        Select-Object -ExpandProperty 'Count' |
        Should -Be 2
}

Describe 'Pester4.when running passing Pester tests' {
    AfterEach { Reset }
    It 'should run the tests' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'One' {
    It 'should pass 1' {
        $true | Should -BeTrue
    }
    It 'should pass again 2' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked 
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 2
        ThenNoDurationReportPresent
    }
}

Describe 'Pester4.when running failing Pester tests' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenTestFile 'FailingTests.ps1' @'
Describe 'Failing' {
    It 'should fail 1' {
        $true | Should -BeFalse
    }
    It 'should fail 2' {
        $true | Should -BeFalse
    }
}
'@
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 2 -PassingCount 0
        ThenTestShouldFail -failureMessage 'Pester tests failed'
    }
}

Describe 'Pester4.when running multiple test scripts' {
    AfterEach { Reset }
    It 'should run all the scripts' {
        Init
        GivenTestFile 'FailingTests.ps1' @'
Describe 'Failing' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        GivenTestFile 'PassingTests.ps1' @'
Describe 'Passing' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked  -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -FailureCount 1 -PassingCount 1
    }
}

Describe 'Pester4.when run multiple times in the same build' {
    AfterEach { Reset }
    It 'should run multiple times' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -PassingCount 2 -FailureCount 0
        ThenTestShouldCreateMultipleReportFiles
    }
}

Describe 'Pester4.when missing path' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'Property "Path": Path is mandatory.'
    }
}

Describe 'Pester4.when a task path is absolute' {
    AfterEach { Reset }
    It 'should fail' {
        $pesterPath = Join-Path -Path $TestDrive.FullName -ChildPath 'SomeFile'
        New-Item -Path $pesterPath
        Init
        GivenTestFile $pesterPath
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenPesterShouldHaveRun -PassingCount 0 -FailureCount 0
        ThenTestShouldFail -failureMessage 'outside\ the\ build\ root'
    }
}

Describe 'Pester4.when showing duration reports' {
    AfterEach { Reset }
    It 'should output the report' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenDescribeDurationReportCount 1
        GivenItDurationReportCount 1
        WhenPesterTaskIsInvoked
        ThenDescribeDurationReportHasRows 1
        ThenItDurationReportHasRows 1
    }
}

Describe 'Pester4.when excluding tests and an exclusion filter doesn''t match' {
    AfterEach { Reset }
    It 'should still run' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' { 
        $true | Should -BeTrue
    }
}
'@
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        GivenExclude '*fail*','Passing*'
        WhenPesterTaskIsInvoked
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 1
    }
}

Describe 'Pester4.when excluding tests and exclusion filters match all paths' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
'@
        GivenTestFile 'FailingTests.ps1' @'
Describe 'FailingTests' {
    It 'should fail' {
        $true | Should -BeFalse
    }
}
'@
        GivenExclude (Join-Path -Path '*' -ChildPath 'Fail*'),(Join-Path -Path '*' -ChildPath 'Passing*')
        WhenPesterTaskIsInvoked -ErrorAction SilentlyContinue
        ThenNoPesterTestFileShouldExist
        ThenTestShouldFail ([regex]::Escape('Found no tests to run. Property "Exclude" matched all paths in the "Path" property.'))
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 0
    }
}

Describe 'Pester4.when not running task in job' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenTestFile 'PassingTests.ps1' @"
Describe 'PassingTests' {
    It 'should run inside Whiskey' {
        Test-Path -Path 'variable:powershellModulesDirectoryName' | Should -BeTrue
        `$powerShellModulesDirectoryName | Should -Be "$($TestPSModulesDirectoryName)"
    }
}
"@
        Mock -CommandName 'Import-Module' -ModuleName 'Whiskey'
        Mock -CommandName 'Invoke-Pester' -ModuleName 'Whiskey' -MockWith {
            @'
<test-results errors="0" failures="0" />
'@ | Set-Content -Path $OutputFile
            return ([pscustomobject]@{ 'TestResult' = [pscustomobject]@{ 'Time' = [TimeSpan]::Zero } })
        }
        WhenPesterTaskIsInvoked -NoJob
        Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -ParameterFilter {
            $Name | Should -BeLike (Join-Path -Path $testRoot -ChildPath ('{0}\Pester\4.*.*\Pester.psd1' -f $TestPSModulesDirectoryName))
            return $true
        }
        Assert-MockCalled -CommandName 'Invoke-Pester' -ModuleName 'Whiskey' -ParameterFilter { 
            Push-Location $testRoot
            try
            {
                $Script | Should -Be (Resolve-Path -Path (Join-Path -Path $testRoot -ChildPath 'PassingTests.ps1') -Relative)
                $Outputfile | Should -BeLike (Resolve-Path -Path (Join-Path -Path $testRoot -ChildPath '.output\pester*.xml') -Relative)
                $OutputFormat | Should -Be 'NUnitXml'
                $PassThru | Should -BeTrue
                return $true
            }
            finally
            {
                Pop-Location
            }
        }
    }
}

Describe 'Pester4.when passing custom arguments' {
    AfterEach { Reset }
    It 'should pass the arguments' {
        Init
        GivenTestFile 'PassingTests.ps1' @'
Describe 'PassingTests' {
    It 'should pass' {
        $true | Should -BeTrue
    }
}
Describe 'FailingTests' {
    It 'should fail' {
        $false | Should -BeTrue
    }
}
'@
        WhenPesterTaskIsInvoked -WithArgument @{
            # Make sure the Pester4 task's default values for these get overwritten
            'OutputFile' = '.output\pester.xml';
            'OutputFormat' = 'JUnitXml';
            # Make sure these do *not* get overwritten.
            'Script' = 'filethatdoesnotexist.ps1'
            'PassThru' = $false;
            # Make sure this gets passed.
            'TestName' = 'PassingTests'
        }
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 1 -AsJUnitXml -ResultFileName 'pester.xml'
    }
}