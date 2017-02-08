Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'

Invoke-WhsCIBuild -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whsbuild.yml' -Resolve) -BuildConfiguration 'Release'

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

function Invoke-NUnitInstall{
    param(
        [switch]
        $WithFailingTests
    )
    if( $WithFailingTests ){
        $assemblyNames = $failingNUnit2TestAssemblyPath
    }
    else{
        $assemblyNames = $passingNUnit2TestAssemblyPath
    }

    $reportPath = Join-path -Path $TestDrive.FullName -ChildPath 'NUnit.xml'
    Invoke-WhsCINunit2Task -path $assemblyNames -ReportPath $reportPath -root $TestDrive.FullName

    Assert-NUnitTestsRun -ReportPath $ReportPath    
    It 'should download NUnit.Runners' {
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\packages\NUnit.Runners.2.6.4') | Should Exist
    }
}

Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' {    
    Invoke-NUnitInstall
}

Describe 'Invoke-WhsCINUnit2Task when running failing NUnit2 tests' {
    $threwException = $false
    $reportPath = Join-path -Path $TestDrive.FullName -ChildPath 'NUnit.xml'
    try{ Invoke-NUnitInstall -withFailingTests }
    catch{ $threwException = $true }

    finally{
        Assert-NUnitTestsNotRun -ReportPath $ReportPath 
        It 'Should Throw an Exception' {
            $threwException | should be $true
        }
    }    
}

Describe 'Invoke-WhsCINUnit2Task when Install-WhsCITool fails' {
    #This doesn't do anything......... Need to figure out how to get it to work Thursday.
    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -ParameterFilter { $NuGetPackageName -eq 'NotAPackage' -and $Version -eq'1.1.1' } -MockWith { return $true }
    Invoke-NUnitInstall

}
