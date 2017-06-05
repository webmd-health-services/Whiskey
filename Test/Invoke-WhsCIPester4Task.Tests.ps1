
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
        $context = New-WhsCITestContext -ForTaskName 'Pester4' -ForOutputDirectory $outputRoot -ForBuildRoot $buildRoot -ForDeveloper
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
        $PassingCount,

        [Switch]
        $WithMissingVersion,

        [Switch]
        $WithMissingPath,

        [String]
        $ShouldFailWithMessage,

        [Switch]
        $WithClean,

        [Switch]
        $WithInvalidVersion
    )

    $defaultVersion = '4.0.3'
    $failed = $false
    $context = New-WhsCIPesterTestContext
    $Global:Error.Clear()
    if ( $WithInvalidVersion )
    {
        $Version = '4.0.999'
        Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' `
                                      -MockWith { return $False }`
                                      -ParameterFilter { $Path -eq $context.BuildRoot }
    }
    if ( $WithMissingPath )
    {
        $taskParameter = @{ 
                        Version = $defaultVersion 
                        }
    }
    elseif( -not $Version -or $WithMissingVersion )
    {
        $taskParameter = @{
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

    $optionalParams = @{ }
    if( $WithClean )
    {
        $optionalParams['Clean'] = $True
        Mock -CommandName 'Uninstall-WhsCITool' -ModuleName 'WhsCI' -MockWith { return $true }
    }    
    try
    {
        Invoke-WhsCIPester4Task -TaskContext $context -TaskParameter $taskParameter @optionalParams
    }
    catch
    {
        $failed = $true
        Write-Error -ErrorRecord $_
    }

    Assert-PesterRan -FailureCount $FailureCount -PassingCount $PassingCount -ReportsIn $context.outputDirectory

    $shouldFail = $FailureCount -gt 1
    if( $ShouldFailWithMessage -or $shouldFail )
    {
        if( $ShouldFailWithMessage )
        {
            It 'should fail' {
                $Global:Error[0] | Should Match $ShouldFailWithMessage
            }
        }
    
        It 'should throw a terminating exception' {
            $failed | Should Be $true
        }
    }
    else
    {
        if( -not $Version )
        {
            $latestPester = ( Find-Module -Name 'Pester' -AllVersions | Where-Object { $_.Version -like '4.*' } ) 
            $latestPester = $latestPester | Sort-Object -Property Version -Descending | Select-Object -First 1
            $Version = $latestPester.Version 
            $Version = '{0}.{1}.{2}' -f ($Version.major, $Version.minor, $Version.build)
        }
        else
        {
            $Version = $Version | ConvertTo-WhsCISemanticVersion
            $Version = '{0}.{1}.{2}' -f ($Version.major, $Version.minor, $Version.patch)
        }
        $pesterDirectoryName = 'Pester.{0}' -f $Version 
        if( $PSVersionTable.PSVersion.Major -ge 5 )
        {
            $pesterDirectoryName = 'Pester\{0}' -f $Version
        }
        $pesterDirectoryName = 'Modules\{0}' -f $pesterDirectoryName

        $pesterPath = Join-Path -Path $context.BuildRoot -ChildPath $pesterDirectoryName

        It 'should pass' {
            $failed | Should Be $false
        }
        if( -not $WithClean )
        {
            It 'Should pass the build root to the Install tool' {
                $pesterPath | Should Exist
           }
        }
        else
        {
            It 'should attempt to uninstall Pester' {
                Assert-MockCalled -CommandName 'Uninstall-WhsCITool' -Times 1 -ModuleName 'WhsCI'
            }            
        }
    }
}

$pesterPassingPath = 'PassingTests' 
$pesterFailingConfig = 'FailingTests' 

Describe 'Invoke-WhsCIBuild when running passing Pester tests' {
    Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 4
}

Describe 'Invoke-WhsCIBuild when running failing Pester tests' {
    $failureMessage = 'Pester tests failed'
    Invoke-PesterTest -Path $pesterFailingConfig -FailureCount 4 -PassingCount 0 -ShouldFailWithMessage $failureMessage -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when running multiple test scripts' {
    Invoke-PesterTest -Path $pesterFailingConfig,$pesterPassingPath -FailureCount 4 -PassingCount 4 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when run multiple times in the same build' {
    Invoke-PesterTest -Path $pesterPassingPath -PassingCount 4  
    Invoke-PesterTest -Path $pesterPassingPath -PassingCount 8  

    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $TestDrive.FullName
    It 'should create multiple report files' {
        Join-Path -Path $outputRoot -ChildPath 'pester-00.xml' | Should Exist
        Join-Path -Path $outputRoot -ChildPath 'pester-01.xml' | Should Exist
    }
}

Describe 'Invoke-WhsCIPester4Task.when missing Path Configuration' {
    $failureMessage = 'Element ''Path'' is mandatory.'
    Invoke-PesterTest -Path $pesterPassingPath -PassingCount 0 -WithMissingPath -ShouldFailWithMessage $failureMessage  -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when version parsed from YAML' {
    # When some versions look like a date and aren't quoted strings, YAML parsers turns them into dates.
    $failureMessage = 'the major version number must always be ''4'''
    Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 0 -Version ([datetime]'3/4/2003') -ShouldFailWithMessage $failureMessage -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when missing Version configuration' {
    Invoke-PesterTest -Path $pesterPassingPath -WithMissingVersion -PassingCount 4 -FailureCount 0
}

Describe 'Invoke-WhsCIPester4Task.when Version property isn''t a version' {
    $version = 'fubar'
    $failureMessage = 'isn''t a valid version'
    Invoke-PesterTest -Path $pesterPassingPath -Version $version -ShouldFailWithMessage $failureMessage -PassingCount 0 -FailureCount 0 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when version of tool doesn''t exist' {
    $failureMessage = 'does not exist'
    Invoke-PesterTest -Path $pesterPassingPath -WithInvalidVersion -ShouldFailWithMessage $failureMessage -PassingCount 0 -FailureCount 0 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when a task path is absolute' {
    $Global:Error.Clear()
    $path = 'C:\FubarSnafu'
    $failureMessage = 'absolute'
    Invoke-PesterTest -Path $path -ShouldFailWithMessage $failureMessage -PassingCount 0 -FailureCount 0 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when Find-Module fails' {
    Mock -CommandName 'Find-Module' -ModuleName 'WhsCI' -MockWith { return $Null }
    Mock -CommandName 'Where-Object' -ModuleName 'WhsCI' -MockWith { return $Null }
    $failureMessage = 'Unable to find a version of Pester 4 to install.'
    Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 0 -WithMissingVersion -ShouldFailWithMessage $failureMessage -ErrorAction SilentlyContinue
    Assert-MockCalled -CommandName 'Find-Module' -Times 1 -ModuleName 'WhsCI'
    Assert-MockCalled -CommandName 'Where-Object' -Times 1 -ModuleName 'WhsCI'
}

Describe 'Invoke-WhsCIPester4Task.when version of tool is less than 4.*' {
    $version = '3.4.3'
    $failureMessage = 'the major version number must always be ''4'''
    Invoke-PesterTest -Path $pesterPassingPath -Version $version -ShouldFailWithMessage $failureMessage -PassingCount 0 -FailureCount 0 -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPester4Task.when running passing Pester tests with Clean Switch' {
     Invoke-PesterTest -Path $pesterPassingPath -FailureCount 0 -PassingCount 0 -withClean
}