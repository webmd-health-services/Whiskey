
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 

function GivenABuiltLibrary
{
    param(
        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $InReleaseMode,

        [Switch]
        $ForBuildServer,

        [string]
        $WithVersion
    )

    $projectRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest' 
    # Make sure output directory gets created by the task
    $outputDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $optionalArgs = @{ }
    if( $InReleaseMode )
    {
        $optionalArgs['BuildConfiguration'] = 'Release'
    }
    else
    {
        $optionalArgs['BuildConfiguration'] = 'Debug'
    }
    if( -not $ForBuildServer )
    {
        $context = New-WhsCITestContext -ForBuildRoot $projectRoot -ForTaskName 'NuGetPack' -ForOutputDirectory $outputDirectory @optionalArgs -ForDeveloper
    }
    else
    {
        $context = New-WhsCITestContext -ForBuildRoot $projectRoot -ForTaskName 'NuGetPack' -ForOutputDirectory $outputDirectory @optionalArgs -ForBuildServer
    }
    if( $WithVersion )
    {
        $Context.Version.NuGetVersion = $WithVersion
    }

    $Global:Error.Clear()
    $project = Join-Path -Path $projectRoot -ChildPath $projectName -Resolve
    'bin','obj','.output' | 
        ForEach-Object { Get-ChildItem -Path $projectRoot -Filter $_ -ErrorAction Ignore } | Remove-Item -Recurse -Force
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Invoke-MSBuild -Path $project -Target 'build' @propertyArg | Out-Null
    return $context
}

function WhenRunningNuGetPackTask
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [Switch]
        $ForProjectThatDoesNotExist,

        [string]
        $ThatFailsWithErrorMessage,

        [Switch]
        $ForMultiplePackages,

        [string]
        $WithVersion
    )

    process 
    {        
        $Global:Error.Clear()        
        if( $ForMultiplePackages )
        {
            $taskParameter = @{
                            Path = @(
                                        $projectName,
                                        $projectName
                                    )
                          }
        }
        else 
        {
            $taskParameter = @{
                            Path = @(
                                        $projectName
                                    )
                          }
        }
        $threwException = $false
        Mock -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -MockWith { return $True }
        try
        {
            if( $WithVersion )
            {
                $Context.Version.NugetVersion = $WithVersion
            }
            if( $ForProjectThatDoesNotExist )
            {
                $taskParameter['Path'] = 'I\do\not\exist.csproj'
            }
            Invoke-WhsCIPublishNuGetLibraryTask -TaskContext $Context -TaskParameter $taskParameter | Out-Null

        }
        catch
        {
            $threwException = $true
            Write-Error $_
        }

        if( $ThatFailsWithErrorMessage )
        {
            It 'should throw an exception' {
                $threwException | Should Be $true
                $Global:Error | Should Not BeNullOrEmpty
                $Global:Error[0] | Should Match $ThatFailsWithErrorMessage
            }
        }
        else
        {
            It 'should not throw an exception' {
                $threwException | Should Be $false
                $Global:Error | Should BeNullOrEmpty
            }
        }

        return $Context

    }
}

function ThenPackageShouldBeCreated
{
    param(
        [string]
        $WithVersion,

        [Switch]
        $ForMultiplePackages,

        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    process
    {
        if( $WithVersion )
        {
            $Context.Version.NuGetVersion = $WithVersion
        }
        It 'should not write any errors' {
            $Global:Error | Should BeNullOrEmpty
        }

        It ('should create NuGet package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $Context.Version.NuGetVersion)) | Should Exist
        }

        It ('should create a NuGet symbols package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $Context.Version.NuGetVersion)) | Should Exist
        }
        if( $Context.byBuildServer )
        {
            if( $ForMultiplePackages )
            {
                It ('should try to publish multiple packages') {
                    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 4 -ParameterFilter {
                        return $ScriptBlock.toString().contains('& $nugetPath push')
                    }
                }
            }
            else
            {
                It ('should try to publish the package') {
                    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 2 -ParameterFilter {
                        return $ScriptBlock.toString().contains('& $nugetPath push')
                    }
                }
            }
            
        }
        else
        {
            It('should not try to publish the package') {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 0 -ParameterFilter {
                    return $ScriptBlock.toString().contains('& $nugetPath push $path ')
                }
            }
        }
    }
}

function ThenPackageShouldNotBeCreated
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    It 'should not create any .nupkg files' {
        (Join-Path -Path $Context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a NuGet package with an invalid project' {
    GivenABuiltLibrary | 
        WhenRunningNuGetPackTask -ForProjectThatDoesNotExist -ThatFailsWithErrorMessage 'does not exist' | 
        ThenPackageShouldNotBeCreated
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a NuGet package' {
    GivenABuiltLibrary | WhenRunningNuGetPackTask | ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCINuGetPackTask.when passed a version' {
    $version = '4.5.6-rc1'
    GivenABuiltLibrary -WithVersion $version | WhenRunningNugetPackTask  | ThenPackageShouldBeCreated -WithVersion $version
}

Describe 'Invoke-WhsCINuGetPackTask.when creating a package built in release mode' {
    GivenABuiltLibrary -InReleaseMode | WhenRunningNugetPackTask | ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCINuGetPackTask.when creating multiple packages for publishing' {
    $global:counter = -1
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    Mock -CommandName 'Invoke-WebRequest' -ModuleName 'WhsCI' -MockWith { 
        $global:counter++       
        if($global:counter -eq 0)
        {
            Invoke-WebRequest -Uri 'http://lcs01d-whs-04.dev.webmd.com:8099/404'
        }
        else
        {
            $global:counter = -1
            return $true
        }
    } -ParameterFilter { $Uri -notlike 'http://lcs01d-whs-04.dev.webmd.com:8099/*' }
    GivenABuiltLibrary -ForBuildServer | WhenRunningNugetPackTask -ForMultiplePackages | ThenPackageShouldBeCreated -ForMultiplePackages
}
