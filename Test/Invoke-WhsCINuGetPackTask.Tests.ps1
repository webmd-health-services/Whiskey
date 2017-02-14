
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function GivenABuiltLibrary
{
    param(
        [Switch]
        $InReleaseMode
    )

    $Global:ERror.Clear()

    $project = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\NUnit2PassingTest.csproj' -Resolve
    $projectRoot = $project | Split-Path
    'bin','obj' | ForEach-Object { Get-ChildItem -Path $projectRoot -Filter $_ } | Remove-Item -Recurse -Force
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Invoke-MSBuild -Path $project -Target 'build' @propertyArg

    return $project    
}

function ThenPackageShouldBeCreated
{
    param(
        [string]
        $WithVersion = '1.2.3-final'
    )

    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }

    It ('should create NuGet package for NUnit2PassingTest') {
        (Join-Path -Path $TestDrive.FullName -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $WithVersion)) | Should Exist
    }

    It ('should create a NuGet symbols package for NUnit2PassingTest') {
        (Join-Path -Path $TestDrive.FullName -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $WithVersion)) | Should Exist
    }
}


Describe 'Invoke-WhsCIBuild.when creating a NuGet package with an invalid project' {
    $Global:Error.Clear()

    $project = Join-Path -Path $TestDrive.FullName -ChildPath 'project.csproj'
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'bin') -ItemType 'Directory' | Out-String | Write-Verbose

    New-MSBuildProject -FileName $project
    
    $threwException = $false
    try
    {
        Invoke-WhsCINuGetPackTask -Path $project -OutputDirectory $TestDrive.FullName -Version '1.0.1-rc1' -BuildConfiguration 'Debug' -ErrorAction SilentlyContinue
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_ -ErrorAction SilentlyContinue
    }

    function Assert-NuGetPackagesNotCreated
    {
        param(
        )

        It 'should throw an exception' {
            $threwException | Should Be $true
            $Global:Error | Should Not BeNullOrEmpty
            $Global:Error[0] | Should Match 'pack command failed'
        }

        $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $TestDrive.FullName
        It 'should not create any .nupkg files' {
            (Join-Path -Path $outputRoot -ChildPath '*.nupkg') | Should Not Exist
        }
    }
    Assert-NuGetPackagesNotCreated
}

Describe 'Invoke-WhsCIBuild.when creating a NuGet package' {
    $project = GivenABuiltLibrary
    Invoke-WhsCINuGetPackTask -Path $project -OutputDirectory $TestDrive.FullName -BuildConfiguration 'Debug'
    ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCIBuild.when piped strings' {
    $project = GivenABuiltLibrary
    $project | Invoke-WhsCINuGetPackTask -OutputDirectory $TestDrive.FullName -BuildConfiguration 'Debug'
    ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCIBuild.when piped file info objects' {
    $project = GivenABuiltLibrary
    Get-Item $project | Invoke-WhsCINuGetPackTask -OutputDirectory $TestDrive.FullName -BuildConfiguration 'Debug'
    ThenPackageShouldBeCreated
}

Describe 'Invoke-WhsCIBuild.when passed a version' {
    $version = '4.5.6-rc1'
    $project = GivenABuiltLibrary
    Get-Item $project | Invoke-WhsCINuGetPackTask -OutputDirectory $TestDrive.FullName -BuildConfiguration 'Debug' -Version $version
    ThenPackageShouldBeCreated -WithVersion $version
}

Describe 'Invoke-WhsCIBuild.when creating a package built in release mode' {
    $project = GivenABuiltLibrary -InReleaseMode
    Get-Item $project | Invoke-WhsCINuGetPackTask -OutputDirectory $TestDrive.FullName -BuildConfiguration 'Release'
    ThenPackageShouldBeCreated 
}
