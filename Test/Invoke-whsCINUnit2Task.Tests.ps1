
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)




Describe 'Invoke-WhsCINUnit2Task when running NUnit tests' {
    $assemblyNames = 'assembly.dll', 'assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly 

}

<#
#design tests based on these tests here.
Instead of calling Invoke-Build, I will want to call my function, but base the assertions on these three.

Describe 'Invoke-WhsCIBuild.when running NUnit tests' {
    $assemblyNames = 'assembly.dll','assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames

    $downloadroot = Join-Path -Path $TestDrive.Fullname -ChildPath 'downloads'
    Invoke-Build -ByJenkins -WithConfig $configPath -DownloadRoot $downloadroot

    Assert-NUnitTestsRun -ConfigurationPath $configPath `
                         -ExpectedAssembly $assemblyNames

    It 'should download NUnitRunners' {
        (Join-Path -Path $downloadroot -ChildPath 'packages\NUnit.Runners.*.*.*') | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild.when running failing NUnit2 tests' {
    $assemblyNames = 'assembly.dll','assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames -ThatFail

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails
    
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly $assemblyNames
}

Describe 'Invoke-WhsCIBuild.when running NUnit2 tests from multiple bin directories' {
    $assemblyNames = 'BinOne\assembly.dll','BinTwo\assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames

    Invoke-Build -ByJenkins -WithConfig $configPath

    $root = Split-Path -Path $configPath -Parent
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly 'assembly.dll' -ExpectedBinRoot (Join-Path -Path $root -ChildPath 'BinOne')
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly 'assembly2.dll' -ExpectedBinRoot (Join-Path -Path $root -ChildPath 'BinTwo')
}
#>