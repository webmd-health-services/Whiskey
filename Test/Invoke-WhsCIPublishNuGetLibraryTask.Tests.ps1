
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 
$context = $null

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
    robocopy $projectRoot $TestDrive.FullName '/MIR' '/R:0'

    # Make sure output directory gets created by the task
    $optionalArgs = @{ }
    if( $InReleaseMode )
    {
        $optionalArgs['BuildConfiguration'] = 'Release'
    }
    else
    {
        $optionalArgs['BuildConfiguration'] = 'Debug'
    }

    $forParam = @{ 'ForDeveloper' = $true }
    if( $ForBuildServer )
    {
        $forParam = @{ 'ForBuildServer' = $true }
    }
    $script:context = New-WhsCITestContext -ForBuildRoot $TestDrive.FullName -ForTaskName 'NuGetPack'  @optionalArgs @forParam
    
    if( $WithVersion )
    {
        $Context.Version.ReleaseVersion = $WithVersion
    }

    $Global:Error.Clear()
    $project = Join-Path -Path $TestDrive.FullName -ChildPath $projectName -Resolve
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Invoke-WhsCIMSBuild -Path $project -Target 'build' @propertyArg | Write-Verbose
}

function WhenRunningNuGetPackTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $ForProjectThatDoesNotExist,

        [string]
        $ThatFailsWithErrorMessage,

        [Switch]
        $ForMultiplePackages,

        [string]
        $WithVersion,

        [Switch]
        $WithCleanSwitch
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

        $optionalParams = @{ }
        if( $WithCleanSwitch )
        {
            $optionalParams['Clean'] = $True
        }
        try
        {
            if( $WithVersion )
            {
                $Context.Version.ReleaseVersion = $WithVersion
            }
            if( $ForProjectThatDoesNotExist )
            {
                $taskParameter['Path'] = 'I\do\not\exist.csproj'
            }
            Invoke-WhsCIPublishNuGetLibraryTask -TaskContext $Context -TaskParameter $taskParameter @optionalParams | Out-Null 

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
                $lastError = $Global:Error[0]
                $lastError | Should -Match $ThatFailsWithErrorMessage
            }
        }
        else
        {
            It 'should not throw an exception' {
                $threwException | Should Be $false
                $Global:Error | Should BeNullOrEmpty
            }
        }

    }
}

function ThenPackageShouldBeCreated
{
    param(
        [string]
        $WithVersion,

        [Switch]
        $ForMultiplePackages,

        [String]
        $WithoutPushingToProgetError,

        [Switch]
        $PackageAlreadyExists
    )

    process
    {
        if( $WithVersion )
        {
            $Context.Version.ReleaseVersion = $WithVersion
        }
        if( $WithoutPushingToProgetError )
        {
            It 'should write push errors' {
                $Global:Error[0] | Should match $WithoutPushingToProgetError             
            }
        }
        else
        {
            It 'should not write any errors' {
                $Global:Error | Should BeNullOrEmpty
            }
        }
        It ('should create NuGet package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $Context.Version.ReleaseVersion)) | Should Exist
        }

        It ('should create a NuGet symbols package for NUnit2PassingTest') {
            (Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $Context.Version.ReleaseVersion)) | Should Exist
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
            elseif( $PackageAlreadyExists )
            {
                It('should not try to publish the package') {
                    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 0 -ParameterFilter {
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
                    return $ScriptBlock.toString().contains('& $nugetPath push')
                }
            }
        }
    }
}

function ThenPackageShouldNotBeCreated
{
    It 'should not create any .nupkg files' {
        (Join-Path -Path $context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package with an invalid project' {
    GivenABuiltLibrary
    WhenRunningNuGetPackTask -ForProjectThatDoesNotExist -ThatFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
    ThenPackageShouldNotBeCreated
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package' {
    GivenABuiltLibrary
    WhenRunningNuGetPackTask
    ThenPackageShouldBeCreated
}

Describe 'Invoke-PublishNuGetLibraryTask.when passed a version' {
    $version = '4.5.6-rc1'
    GivenABuiltLibrary -WithVersion $version
    WhenRunningNugetPackTask
    ThenPackageShouldBeCreated -WithVersion $version
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a package built in release mode' {
    GivenABuiltLibrary -InReleaseMode
    WhenRunningNugetPackTask
    ThenPackageShouldBeCreated
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating multiple packages for publishing' {
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
            return $True
        }
    } -ParameterFilter { $Uri -notlike 'http://lcs01d-whs-04.dev.webmd.com:8099/*' }
    GivenABuiltLibrary -ForBuildServer
    WhenRunningNugetPackTask -ForMultiplePackages
    ThenPackageShouldBeCreated -ForMultiplePackages
}

Describe 'Invoke-PublishNuGetLibraryTask.when push command fails' {
    $errorMessage = 'Failed to publish NuGet package'
    $Global:error.Clear()
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    Mock -CommandName 'Invoke-WebRequest' -ModuleName 'WhsCI' -MockWith { 
        Invoke-WebRequest -Uri 'http://lcs01d-whs-04.dev.webmd.com:8099/404'
    } -ParameterFilter { $Uri -notlike 'http://lcs01d-whs-04.dev.webmd.com:8099/*' }
    GivenABuiltLibrary -ForBuildServer
    WhenRunningNugetPackTask -ThatFailsWithErrorMessage $errorMessage -ErrorAction SilentlyContinue
    ThenPackageShouldBeCreated -WithoutPushingToProgetError $errorMessage
}

Describe 'Invoke-PublishNuGetLibraryTask.when package already exists' {
    $errorMessage = 'already exists'
    $Global:error.Clear()
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    Mock -CommandName 'Invoke-WebRequest' -ModuleName 'WhsCI' -MockWith { return $True}
    GivenABuiltLibrary -ForBuildServer
    WhenRunningNugetPackTask -ThatFailsWithErrorMessage $errorMessage -ErrorAction SilentlyContinue
    ThenPackageShouldBeCreated -PackageAlreadyExists -WithoutPushingToProgetError $errorMessage 
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating WebRequest fails' {
    $errorMessage = 'Failure checking if'
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    Mock -CommandName 'Invoke-WebRequest' -ModuleName 'WhsCI' -MockWith { 
        Invoke-WebRequest -Uri 'http://lcs01d-whs-04.dev.webmd.com:8099/500'
    } -ParameterFilter { $Uri -notlike 'http://lcs01d-whs-04.dev.webmd.com:8099/*' }
    GivenABuiltLibrary -ForBuildServer
    WhenRunningNugetPackTask -ThatFailsWithErrorMessage $errorMessage -ErrorAction SilentlyContinue
    ThenPackageShouldBeCreated -PackageAlreadyExists -WithoutPushingToProgetError $errorMessage 
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package with Clean switch' {    
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
    Mock -CommandName 'Invoke-WebRequest' -ModuleName 'WhsCI' -MockWith { 
    Invoke-WebRequest -Uri 'http://lcs01d-whs-04.dev.webmd.com:8099/404'
    } -ParameterFilter { $Uri -notlike 'http://lcs01d-whs-04.dev.webmd.com:8099/*' }
    
    GivenABuiltLibrary -ForBuildServer
    WhenRunningNuGetPackTask -WithCleanSwitch

    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }

    It('should not create the package') {
        Get-ChildItem $context.OutputDirectory | Should -BeNullOrEmpty
    }

    It('should not try to publish the package') {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 0 -ParameterFilter {
            return $ScriptBlock.toString().contains('& $nugetPath push')
        }
    }
}