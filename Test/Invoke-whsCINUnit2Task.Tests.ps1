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

Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' {


    $assemblyNames = $passingNUnit2TestAssemblyPath
    $ReportPath = Join-Path -path $TestDrive.FullName -ChildPath 'NUnit.xml'

    $downloadroot = Join-Path -Path $TestDrive.Fullname -ChildPath 'downloads'
    Invoke-WhsCINunit2Task -DownloadRoot $downloadroot -path $assemblyNames -ReportPath $ReportPath -root $TestDrive.FullName

    Assert-NUnitTestsRun -ReportPath $ReportPath

    It 'should download NUnitRunners' {
        (Join-Path -Path $downloadroot -ChildPath 'packages\NUnit.Runners.*.*.*') | Should Exist
    }

}


Describe 'Invoke-WhsCINUnit2Task when running failing NUnit2 tests' {
    $assemblyNames = $failingNUnit2TestAssemblyPath
    $ReportPath = Join-path -Path $TestDrive.FullName -ChildPath 'NUnit.xml'

    $downloadroot = Join-Path -Path $TestDrive.Fullname -ChildPath 'downloads'

    $threwException = $false

    try{
        Invoke-WhsCINunit2Task -DownloadRoot $downloadroot -path $assemblyNames -ReportPath $ReportPath -root $TestDrive.FullName
    }
    catch{
        $threwException = $true
    }
    Assert-NUnitTestsNotRun -ReportPath $ReportPath
    It 'Should Throw an Exception' {
        $threwException | should be $true
    }
    
}


Describe 'Invoke-WhsCINUnit2Task when running NUnit2 tests from multiple bin directories' {
    $assemblyNames = $passingNUnit2TestAssemblyPath
    $ReportPath = Join-Path -Path $TestDrive.FullName -ChildPath 'NUnit.xml'

    $downloadroot = Join-Path -Path $TestDrive.Fullname -ChildPath 'downloads'
    Invoke-WhsCINunit2Task -DownloadRoot $downloadroot -path $assemblyNames -ReportPath $ReportPath -root $TestDrive.FullName

    Assert-NUnitTestsRun -ReportPath $ReportPath
    It 'should download NUnitRunners' {
        (Join-Path -Path $downloadroot -ChildPath 'packages\NUnit.Runners.*.*.*') | Should Exist
    }
}
