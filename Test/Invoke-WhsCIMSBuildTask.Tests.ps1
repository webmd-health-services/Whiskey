
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'


Describe 'Invoke-WhsCIMSBuildTask.when building real projects' {

    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]"1.2.3-rc.1+build" }

    $failingNUnit2TestAssemblyPath,$passingNUnit2TestAssemblyPath | Remove-Item -Force -ErrorAction Ignore

    $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForVersion "1.2.3-rc.1+build" -ForBuildServer
    $taskParameter = @{
                        Path = @(
                                    'NUnit2FailingTest\NUnit2FailingTest.sln',
                                    'NUnit2PassingTest\NUnit2PassingTest.sln'
                                )
                      }

    # Get rid of any existing packages directories.
    Get-ChildItem -Path $PSScriptRoot 'packages' -Recurse -Directory | Remove-Item -Recurse -Force
    
    $errors = @()
    Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter

    It 'should write no errors' {
        $errors | Should Not Match 'MSBuild'
    }

    It 'should restore NuGet packages' {
        Get-ChildItem -Path $PSScriptRoot -Filter 'packages' -Recurse -Directory | Should Not BeNullOrEmpty
    }

    It 'should build assemblies' {
        $failingNUnit2TestAssemblyPath | Should Exist
        $passingNUnit2TestAssemblyPath | Should Exist
    }

    foreach( $assembly in @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath ) )
    {
        It ('should version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
            $fileInfo = Get-Item -Path $assembly
            $fileVersionInfo = $fileInfo.VersionInfo
            $fileVersionInfo.FileVersion | Should Be $context.Version.Version.ToString()
            $fileVersionInfo.ProductVersion | Should Be ('{0}' -f $context.Version)
        }
    }
}

Describe 'Invoke-WhsCIMSBuildTask.when compilation fails' {
    $context = New-WhsCITestContext 
    $taskParameter = @{
                        Path = @(
                                    'ThisWillFail.sln',
                                    'ThisWillAlsoFail.sln'
                                )
                      }
    $threwException = $false
    try
    {
        Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
    }
    catch
    {
        $threwException = $true
    }
    It 'should throw an exception'{
        $threwException | Should Be $true
    }
}

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is not included' {
    $context = New-WhsCITestContext
    $taskParameter = @{ }
    $threwException = $false
    $Global:Error.Clear()

    try
    {
        Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter 
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

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is invalid' {
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
        Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter 
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

Describe 'Invoke-WhsCIBuild.when a developer is compiling dotNET project' {
    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $false }
    $context = New-WhsCITestContext (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -ForVersion "1.1.1-rc.1+build"
    $taskParameter = @{
                        Path = @(
                                    'NUnit2FailingTest\NUnit2FailingTest.sln',
                                    'NUnit2PassingTest\NUnit2PassingTest.sln'
                                )
                      }

    Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter

    foreach( $assembly in @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath ) )
    {
        It ('should not version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
            $fileInfo = Get-Item -Path $assembly
            $fileVersionInfo = $fileInfo.VersionInfo
            $fileVersionInfo.FileVersion | Should Not Be $context.Version.Version.ToString()
            $fileVersionInfo.ProductVersion | Should Not Be ('{0}' -f $context.Version)
        }
    }
}
