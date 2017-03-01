
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function Assert-PesterRan
{
    param(
        [string]
        $ReportsIn,

        [Parameter(Mandatory=$true)]
        [int]
        $FailureCount,
            
        [Parameter(Mandatory=$true)]
        [int]
        $PassingCount
    )

    $testReports = Get-ChildItem -Path $ReportsIn -Filter 'pester-*.xml'
    It 'should run pester tests' {
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
    It ('should run {0} tests' -f $expectedTotal) {
        $total | Should Be $expectedTotal
    }

    It ('should have {0} failed tests' -f $FailureCount) {
        $failed | Should Be $FailureCount
    }

    It ('should run {0} passing tests' -f $PassingCount) {
        $passed | Should Be $PassingCount
    }
}

function New-WhsCIPesterTestContext 
{
    param()
    process
    {
        $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $TestDrive.FullName
        if( -not (Test-Path -Path $outputRoot -PathType Container) )
        {
            New-Item -Path $outputRoot -ItemType 'Directory'
        }
        $buildRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Pester' -Resolve
        $context = New-WhsCITestContext -ForTaskName 'Pester3' -ForOutputDirectory $outputRoot -ForBuildRoot $buildRoot
        return $context
    }
}

function Invoke-PesterTest
{
    [CmdletBinding()]
    param(
        [string[]]
        $Path,

        [object]
        $Version,

        [int]
        $FailureCount,

        [int]
        $PassingCount
    )

    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -Verifiable -MockWith { Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\Pester\Pester.psd1' -Resolve }.GetNewClosure()
    
    $defaultVersion = '3.4.3'
    $failed = $false
    $context = New-WhsCIPesterTestContext
    if( -not $Version )
    {
        $taskParameter = @{
                        Version = $defaultVersion;
                        Path = @(
                                    $Path
                                )
                        }
    }
    else
    {
        $taskParameter = @{
                        Version = $Version;
                        Path = @(
                                    $Path
                                )
                        }
    }
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter
    }
    catch
    {
        $failed = $true
        Write-Error -ErrorRecord $_
    }

    Assert-PesterRan -FailureCount $FailureCount -PassingCount $PassingCount -ReportsIn $context.outputDirectory

    $shouldFail = $FailureCount -gt 1
    if( $shouldFail )
    {
        It 'should fail and throw a terminating exception' {
            $shouldFail | Should Be $true
        }
    }
    else
    {
        It 'should pass' {
            $failed | Should Be $false
        }
    }

    $moduleRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\Modules'
    
    It 'should download Pester' {
        Assert-MockCalled -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -ParameterFilter {
            #$DebugPreference = 'Continue';
            Write-Debug -Message ('ModuleName  expected  Pester')
            Write-Debug -Message ('            actual    {0}' -f $ModuleName)
            Write-Debug -Message ('Version     expected  {0}' -f $defaultVersion)
            Write-Debug -Message ('            actual    {0}' -f $Version)
            $ModuleName -eq 'Pester' -and $Version -eq $defaultVersion
        }
    }
}

$pesterPassingPath = 'PassingTests' 
$pesterFailingConfig = 'FailingTests' 

Describe 'Invoke-WhsCIBuild when running passing Pester tests' {
    Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 4
}

Describe 'Invoke-WhsCIBuild when running failing Pester tests' {
    Invoke-PesterTest -Path $pesterFailingConfig -FailureCount 4 -PassingCount 0 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester3Task.when running multiple test scripts' {
    Invoke-PesterTest -Path $pesterFailingConfig,$pesterPassingPath -FailureCount 4 -PassingCount 4 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester3Task.when run multiple times in the same build' {
    Invoke-PesterTest -Path $pesterPassingPath -PassingCount 4  
    Invoke-PesterTest -Path $pesterPassingPath -PassingCount 8  

    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $TestDrive.FullName
    It 'should create multiple report files' {
        Join-Path -Path $outputRoot -ChildPath 'pester-00.xml' | Should Exist
        Join-Path -Path $outputRoot -ChildPath 'pester-01.xml' | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild when version parsed from YAML' {
    # When some versions look like a date and aren't quoted strings, YAML parsers turns them into dates.
    Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 4 -Version ([datetime]'3/4/2003')
}

Describe 'Invoke-WhsCIPester3Task.when missing Version configuration' {
    $Global:Error.Clear()
    $taskParameter = @{
                        Version = '';
                        path = @(
                                    $pesterPassingPath
                        )
                    }
    $context = New-WhsCIPesterTestContext
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter
    }
    catch
    {
    }

    It 'should fail' {
        $Global:Error[0] | Should Match 'is mandatory'
    }

    It 'should not run any tests' {
        Get-ChildItem -Path $context.OutputDirectory | Should BeNullOrEmpty
    }
}

Describe 'Invoke-WhsCIPester3Task.when Version property isn''t a version' {
    $Global:Error.Clear()
    $taskParameter = @{
                        Version = 'fubar';
                        path = @(
                                    $pesterPassingPath
                        )
                    }
    $context = New-WhsCIPesterTestContext 
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    }
    catch
    {
    }

    It 'should fail' {
        $Global:Error[0] | Should Match 'isn''t a valid version'
    }

    It 'should not run any tests' {
        Get-ChildItem -Path $context.OutputDirectory | Should BeNullOrEmpty
        
    }
}

Describe 'Invoke-WhsCIPester3Task.when version of tool doesn''t exist' {
    $Global:Error.Clear()
    $taskParameter = @{
                        Version = '3.0.0';
                        path = @(
                                    $pesterPassingPath
                        )
                    }
    $context = New-WhsCIPesterTestContext 
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    }
    catch
    {
    }

    It 'should fail' {
        $Global:Error[0] | Should Match 'does not exist'
    }

    It 'should not run any tests' {
        Get-ChildItem -Path $context.OutputDirectory | Should BeNullOrEmpty
    }
}

Describe 'Invoke-WhsCIPester3Task.when Version property is valid, but passed as a dateTime object' {
    $Global:Error.Clear()
    $taskParameter = @{
                        #this "date" is a valid version 3.4.3 and should be converted by ConvertTo-WhsCISemanticVersion
                        Version = [DateTime]'3/4/2003 12:00:00 AM';
                        path = @(
                                    $pesterPassingPath
                        )
                    }
    $context = New-WhsCIPesterTestContext 
    $failed = $false
    $FailureCount = 0
    $PassingCount = 4
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    }
    catch
    {
        $failed = $true
        Write-Error -ErrorRecord $_
    }

    It 'should not fail' {
        $failed | Should be $false
        $Global:Error | Should BeNullOrEmpty
    }
    Assert-PesterRan -FailureCount $FailureCount -PassingCount $PassingCount -ReportsIn $context.outputDirectory
}

Describe 'Invoke-WhsCIPester3Task.when a task path is absolute' {
    $Global:Error.Clear()
    $path = 'C:\FubarSnafu'
    $taskParameter = @{
                        path = @(                                    
                                    $path
                        )
                    }
    $context = New-WhsCIPesterTestContext 
    try
    {
        Invoke-WhsCIPester3Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    }
    catch
    {
    }

    It 'should write an error that the path is absolute' {
        $Global:Error[0] | Should Match 'absolute'
    }

    It 'should not run any tests' {
        Get-ChildItem -Path $context.OutputDirectory | Should BeNullOrEmpty
    }
}