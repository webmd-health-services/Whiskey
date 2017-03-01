
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'


function Invoke-MSBuild
{
    param(
        [Switch]
        $ThatFails,

        [string[]]
        $On,

        [Switch]
        $InReleaseMode,

        [Switch]
        $AsDeveloper,

        [Switch]
        $ForRealProjects,

        [String[]]
        $ForAssemblies,

        [String]
        $WithError
    )

    Process
    {
        $optionalArgs = @{ }
        $threwException = $false
        $Global:Error.Clear()
        
        $runByBuildServerMock = { return $true }
        $taskParameter = @{ }
        if( $On )
        {
            $taskParameter['Path'] = $On
        }

        if ( $InReleaseMode )
        {
            $optionalArgs['InReleaseMode'] = $true
        }

        if ( $AsDeveloper )
        {
            $version = [SemVersion.SemanticVersion]"1.2.3-rc.1+build"
            $runByBuildServerMock = { return $false }
            $optionalArgs['ByDeveloper'] = $true
        }
        else
        {
            $version = [SemVersion.SemanticVersion]"1.1.1-rc.1+build"
            $optionalArgs['ByBuildServer'] = $true
        }

        # Get rid of any existing packages directories.
        Get-ChildItem -Path $PSScriptRoot 'packages' -Recurse -Directory | Remove-Item -Recurse -Force

        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith $runByBuildServerMock
        MOck -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $version }.GetNewClosure()
        $context = New-WhsCITestContext -ForBuildRoot (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') @optionalArgs
        $assembliesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies'
        # Set aside the AssemblyInfo.cs files so we can restore them late
        Get-ChildItem -Path $assembliesRoot -Filter 'AssemblyInfo.cs' -Recurse |
            ForEach-Object { Copy-Item -Path $_.FullName -Destination ('{0}.orig' -f $_.FullName) }
        $errors = @()
        try
        {
            Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
        }
        catch
        {
            $threwException = $true
        }
        finally
        {
            # Restore the original AssemblyInfo.cs files.
            Get-ChildItem -Path $assembliesRoot -Filter 'AssemblyInfo.cs.orig' -Recurse |
                ForEach-Object { Move-Item -Path $_.FullName -Destination ($_.FullName -replace '\.orig$','') -Force }
        }
        
        if( $WithError )
        {
            It 'should should write an error'{
                $Global:Error | Should Match ( $WithError )
            }
        }      
        if( $ThatFails )
        {
            It 'should throw an exception'{
                $threwException | Should Be $true
            }
        }
        #Valid Path
        else
        {
            It 'should not throw an exception'{
                $threwException | Should Be $false
            }

            It 'should write no errors' {
                $errors | Should Not Match 'MSBuild'
            }

            It 'should restore NuGet packages' {
                Get-ChildItem -Path $PSScriptRoot -Filter 'packages' -Recurse -Directory | Should Not BeNullOrEmpty
            }

            foreach( $assembly in $ForAssemblies )
            {
                It ('should build the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
                    $assembly | Should Exist
                }
            }

            foreach( $assembly in $ForAssemblies )
            {
                It ('should version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
                    $fileInfo = Get-Item -Path $assembly
                    $fileVersionInfo = $fileInfo.VersionInfo
                    $fileVersionInfo.FileVersion | Should Be $context.Version.Version.ToString()
                    $fileVersionInfo.ProductVersion | Should Be ('{0}' -f $context.Version)
                }
            }
        }  
    }
}

Describe 'Invoke-WhsCIMSBuildTask.when building real projects' {
    $assemblies = @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath )
    Invoke-MSBuild -On @(
                                        'NUnit2FailingTest\NUnit2FailingTest.sln',
                                        'NUnit2PassingTest\NUnit2PassingTest.sln'
                                    ) -InReleaseMode -ForAssemblies $assemblies
}

Describe 'Invoke-WhsCIMSBuildTask.when compilation fails' {
    Invoke-MSBuild -ThatFails -On @(
                                    'ThisWillFail.sln',
                                    'ThisWillAlsoFail.sln'
                                )
}

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is not included' {
    $errorMatch = [regex]::Escape('Element ''Path'' is mandatory')
    Invoke-MSBuild -ThatFails -WithError $errorMatch
}

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is invalid' {
    $errorMatch = [regex]::Escape('does not exist.')
    Invoke-MSBuild -ThatFails -On 'I\do\not\exist' -WithError $errorMatch
}

Describe 'Invoke-WhsCIBuild.when a developer is compiling dotNET project' {
    $assemblies = @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath )
    Invoke-MSBuild -On @(
                                        'NUnit2FailingTest\NUnit2FailingTest.sln',
                                        'NUnit2PassingTest\NUnit2PassingTest.sln'
                                    ) -AsDeveloper -ForAssemblies $assemblies
}
