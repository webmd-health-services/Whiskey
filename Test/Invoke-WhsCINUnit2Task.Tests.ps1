Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'



function Assert-NUnitTestsRun
{
    param(
        [string]
        $ReportPath
    )
    It 'should run NUnit tests' {
        $ReportPath | Split-Path | ForEach-Object { Get-WhsCIOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }   
}

function Assert-NUnitTestsNotRun
{
    param(
        [string]
        $ReportPath
    )
    It 'should not run NUnit tests' {
        $ReportPath | Split-Path | ForEach-Object { Get-WhsCIOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}

function Invoke-RunNUnit2Task
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [switch]
        $WithFailingTests
    )

    if( $WithFailingTests )
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
                                    'NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'
                                )
                      }
    }
     
    $ReportPath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $TaskContext.TaskIndex)
    Invoke-WhsCINUnit2Task -TaskContext $TaskContext -TaskParameter $taskParameter
    Assert-NUnitTestsRun -ReportPath $ReportPath    
    It 'should download NUnit.Runners' {
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\packages\NUnit.Runners.2.6.4') | Should Exist
    }
}


Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' { 
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { $false }
    $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies')  -InReleaseMode
    $taskParameter = @{
                        Path = @(
                                    'NUnit2FailingTest\NUnit2FailingTest.sln',
                                    'NUnit2PassingTest\NUnit2PassingTest.sln'
                                )
                      }

    Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
    Invoke-RunNUnit2Task -TaskContext $context
}

Describe 'Invoke-WhsCINUnit2Task when running failing NUnit2 tests' {
    $threwException = $false
    $context = New-WhsCITestContext
    $ReportPath = Join-Path -Path $context.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $context.TaskIndex)
    try
    {   
        Invoke-RunNUnit2Task -TaskContext $context -withFailingTests 
    }
    catch
    { 
        $threwException = $true 
    }

    finally
    {
        Assert-NUnitTestsNotRun -ReportPath $reportPath 
        It 'Should Throw an Exception' {
            $threwException | should be $true
        }
    }    
}

Describe 'Invoke-WhsCINUnit2Task when Install-WhsCITool fails' {
    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -MockWith { return $false }
    $Global:Error.Clear()
    $threwException = $false
    $context = New-WhsCITestContext
    try
    {
        Invoke-RunNUnit2Task -TaskContext $context -ErrorAction silentlyContinue
    }
    catch
    {
        $threwException = $true
    }
    It 'should throw an exception' {
        $threwException | should be $true
    }
}

Describe 'Invoke-WhsCINUnit2Task when Path Parameter is not included' {
    $context = New-WhsCITestContext
    $taskParameter = @{ }
    $threwException = $false
    $Global:Error.Clear()

    try
    {
        Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $taskParameter 
    }
    catch
    {
        $threwException = $true
    }
    It 'should throw an exception'{
        $threwException | Should Be $true
        $Global:Error | Should Match ([regex]::Escape('Element ''Path'' is mandatory'))
    }
}

Describe 'Invoke-WhsCINUnit2Task when Path Parameter is invalid' {
    $context = New-WhsCITestContext
    $taskParameter = @{
                        Path = @(
                                    'I\do\not\exist'
                                )
                      }
    $threwException = $false
    $Global:Error.Clear()

    try
    {
        Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $taskParameter 
    }
    catch
    {
        $threwException = $true
    }
    It 'should throw an exception'{
        $threwException | Should Be $true
        $Global:Error | Should Match ([regex]::Escape('does not exist.'))
    }

}

Describe 'Invoke-WhsCINUnit2Task when NUnit Console Path is invalid and Join-Path -resolve fails' {
    Mock -CommandName 'Join-Path' -ModuleName 'WhsCI' -MockWith { Write-Error 'Path does not exist!' } -ParameterFilter { $ChildPath -eq 'nunit-console.exe' }

    #Build a valid context and task parameter as we are just trying to isolate the testing of Join-path -Resolve 
    $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies')
    $taskParameter = @{
                        Path = @(
                                    'NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
                                )
                      }
    $threwException = $false
    $Global:Error.Clear()

    try
    {
        Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction silentlyContinue
    }
    catch
    {
        $threwException = $true
    }
    It 'should write an error' {
        $Global:Error[0] | Should Match ([regex]::Escape('was installed, but couldn''t find nunit-console.exe'))
    }
    It 'should throw an exception as a result'{
        $threwException | Should Be $true
    }
}