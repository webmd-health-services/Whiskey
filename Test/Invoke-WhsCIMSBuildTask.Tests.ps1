
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

        [Switch]
        $WithFailingSolutions,

        [Switch]
        $WithNoPath,

        [Switch]
        $WithInvalidPath,
        
        [Switch]
        $InReleaseMode,

        [Switch]
        $WhileBuildingDotNetProjects,

        [Switch]
        $ForRealProjects,

        [String[]]
        $ForAssemblies,

        [String]
        $WithError
    )

    Process
    {
        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
        $context = New-WhsCITestContext 
        $threwException = $false
        $Global:Error.Clear()
        
        if( $WithFailingSolutions )
        {
            $taskParameter = @{
                        Path = @(
                                    'ThisWillFail.sln',
                                    'ThisWillAlsoFail.sln'
                                )
                            }    
        }
        elseif( $WithNoPath )
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
        #Valid Path
        else
        {
            if ( $InReleaseMode )
            {
                Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
                $context = New-WhsCITestContext (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies') -InReleaseMode
                
            }
            elseif ( $WhileBuildingDotNetProjects )
            {
                Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $false }
                $context = New-WhsCITestContext (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies')
                $context.Version = '1.1.1'
                $context.SemanticVersion = "1.1.1-rc.1+build"
            }
            else
            {
                $context = New-WhsCITestContext (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies')                
            }
            # Get rid of any existing packages directories.
            Get-ChildItem -Path $PSScriptRoot 'packages' -Recurse -Directory | Remove-Item -Recurse -Force
            $taskParameter = @{
                                Path = @(
                                            'NUnit2FailingTest\NUnit2FailingTest.sln',
                                            'NUnit2PassingTest\NUnit2PassingTest.sln'
                                        )
                              }                              
        }
        $errors = @()
        try
        {
            Invoke-WhsCIMSBuildTask -TaskContext $context -TaskParameter $taskParameter
        }
        catch
        {
            $threwException = $true
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
            if( $ForRealProjects )
            {
                foreach( $assembly in $ForAssemblies )
                {
                    It ('should version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
                        $fileInfo = Get-Item -Path $assembly
                        $fileVersionInfo = $fileInfo.VersionInfo
                        $fileVersionInfo.FileVersion | Should Be $context.Version.ToString()
                        $fileVersionInfo.ProductVersion | Should Be ('{0}' -f $context.SemanticVersion)
                    }
                }
             }
             elseif ( $WhileBuildingDotNetProjects )
             {
                
                foreach( $assembly in $ForAssemblies )
                {
                    It ('should not version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
                        $fileInfo = Get-Item -Path $assembly
                        $fileVersionInfo = $fileInfo.VersionInfo
                        $fileVersionInfo.FileVersion | Should Not Be $context.Version.ToString()
                        $fileVersionInfo.ProductVersion | Should Not Be ('{0}' -f $context.SemanticVersion)
                    }
                }
             }
        }  
    }
}

Describe 'Invoke-WhsCIMSBuildTask.when building real projects' {
    $assemblies = @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath )
    Invoke-MSBuild -ForRealProjects -InReleaseMode -ForAssemblies $assemblies
}

Describe 'Invoke-WhsCIMSBuildTask.when compilation fails' {
    Invoke-MSBuild -ThatFails -WithFailingSolutions
}

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is not included' {
    $errorMatch = [regex]::Escape('Element ''Path'' is mandatory')
    Invoke-MSBuild -ThatFails -WithNoPath -WithError $errorMatch
}

Describe 'Invoke-WhsCIMSBuildTask. when Path Parameter is invalid' {
    $errorMatch = [regex]::Escape('does not exist.')
    Invoke-MSBuild -ThatFails -WithInvalidPath -WithError $errorMatch
}

Describe 'Invoke-WhsCIBuild.when a developer is compiling dotNET project' {
    $assemblies = @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath )
    Invoke-MSBuild -WhileBuildingDotNetProjects -ForAssemblies $assemblies
}
