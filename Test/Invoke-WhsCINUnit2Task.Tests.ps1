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
        $WithError
    )
    Process
    {
        if ( $InReleaseMode )
        {
            $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies')  -InReleaseMode -ForDeveloper
        }
        else
        {
            $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForDeveloper
        }
        $threwException = $false
        $Global:Error.Clear()

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
        elseif( $WhenJoinPathResolveFails )
        {
            $taskParameter = @{
                                Path = @(
                                            'NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
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
        elseif( $WithRunningTests )
        {
            $taskParameter = @{
                            Path = @(
                                        'NUnit2FailingTest\NUnit2FailingTest.sln',
                                        'NUnit2PassingTest\NUnit2PassingTest.sln'
                                    )
                          }
            Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
        }

        try
        {
            Invoke-WhsCINUnit2Task -TaskContext $context -TaskParameter $taskParameter -ErrorAction SilentlyContinue
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
        if( $ThatFails )
        {
            Assert-NUnitTestsNotRun -ReportPath $reportPath
            It 'should throw an exception'{
                $threwException | Should Be $true
            }
        }
        else
        {
            Assert-NUnitTestsRun -ReportPath $ReportPath    
            It 'should download NUnit.Runners' {
                (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\packages\NUnit.Runners.2.6.4') | Should Exist
            }
        }
        
    }
}


Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' { 
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { $false }
    Invoke-NUnitTask -WithRunningTests -InReleaseMode
    return
}

Describe 'Invoke-WhsCINUnit2Task when running failing NUnit2 tests' {
    Invoke-NUnitTask -ThatFails -WithFailingTests
    return   
}

Describe 'Invoke-WhsCINUnit2Task when Install-WhsCITool fails' {
    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -MockWith { return $false }
    Invoke-NUnitTask -ThatFails
    return
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