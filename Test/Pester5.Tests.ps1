Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

BeforeAll{
    function New-Thing{
        "Thing"
    }

    function Get-Num{
        return 1
    }

    function Init
    {
        $script:taskParameter = @{}
        $script:version = $null
        $script:failed = $false
        $script:taskParameter = @{}
        $Global:Error.Clear()

        $script:testRoot = New-WhiskeyTestRoot

        $script:context = New-WhiskeyTestContext -ForTaskName 'Pester5' `
                                                -ForDeveloper `
                                                -ForBuildRoot $testRoot `
                                                -IncludePSModule 'Pester'

        $pesterModuleRoot = Join-Path -Path $testRoot -ChildPath ('{0}\Pester' -f $TestPSModulesDirectoryName)
        Get-ChildItem -Path $pesterModuleRoot -ErrorAction Ignore | 
            Where-Object { $_.Name -notlike '5.*' } |
            Remove-Item -Recurse -Force
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

        if( $WithArgument.ContainsKey('Script') )
        {
            $taskParameter['Script'] = $WithArgument['Script']
            $WithArgument.Remove('Script')
            if( $taskParameter.ContainsKey('Path') )
            {
                $taskParameter.Remove('Path')
            }
        }

        try
        {
            $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'Pester5'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
            # $Error | Where-Object { $_ -match '"Path" value must be a single string'} | Should -Not -BeNullOrEmpty 
        }
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
            Should -Invoke -CommandName 'Publish-WhiskeyPesterTestResult' `
                            -ModuleName 'Whiskey' `
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
}

AfterAll{
    function Reset
    {
        Reset-WhiskeyTestPSModule
    }
}


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

Describe "Get-Num"{
    It "should return 1"{
        Get-Num | Should -Be 1
    }
}

Describe "New-thing"{
    BeforeEach{
        Mock New-Thing {return "That"}
    }
    It "should not return a thing"{
        New-Thing | Should -Not -Be "Thing"
        Should -Invoke -Commandname New-Thing -Times 1
    }
}

# This is the one I'm having trouble with
Describe 'Pester5.when running passing Pester tests' {
    BeforeEach{
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

    }

    It 'should run the tests' {
        WhenPesterTaskIsInvoked

        #Fails when it tries to verify that the Mock has run 
        ThenPesterShouldHaveRun -FailureCount 0 -PassingCount 2
        ThenNoDurationReportPresent
    }

    AfterEach{ 
        Reset 
    }
}

# Got this one working
Describe 'Pester5.when passing hashtable to script property with multiple paths' {
    It 'should pass arguments' {
        Init
        WhenPesterTaskIsInvoked -WithArgument @{
            'Script' = @{
                'Path' = ('Path1.ps1','Path2.ps1')
            }
        } -ErrorAction SilentlyContinue
        ThenTestShouldFail '"Path" value must be a single string'
    }
    AfterEach { 
        Reset 
    }
}