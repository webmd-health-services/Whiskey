
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Import-WhiskeyTestModule 'VSSetup'

    $script:testRoot = $null
    $script:projectName = 'NuGetPack.csproj'
    $script:context = $null
    $script:nugetUri = $null
    $script:apiKey = $null
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:threwException = $false
    $script:byBuildServer = $false
    $script:version = $null

    function GivenABuiltLibrary
    {
        param(
            [switch]$ThatDoesNotExist,

            [switch]$InReleaseMode
        )

    @'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="12.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
    <ProjectGuid>{A4366E0A-29F0-4F5E-B6CD-C35F022FB924}</ProjectGuid>
    <OutputType>Library</OutputType>
    <RootNamespace>NuGetPack</RootNamespace>
    <AssemblyName>NuGetPack</AssemblyName>
    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
    <FileAlignment>512</FileAlignment>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    <DebugSymbols>true</DebugSymbols>
    <DebugType>full</DebugType>
    <Optimize>false</Optimize>
    <OutputPath>bin\Debug\</OutputPath>
    <DefineConstants>DEBUG;TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
    <DebugType>pdbonly</DebugType>
    <Optimize>true</Optimize>
    <OutputPath>bin\Release\</OutputPath>
    <DefineConstants>TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="NoOp.cs" />
  </ItemGroup>
  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
       Other similar extension points exist, see Microsoft.Common.targets.
  <Target Name="BeforeBuild">
  </Target>
  <Target Name="AfterBuild">
  </Target>
  -->
</Project>
'@ | Set-Content -Path (Join-Path -Path $script:testRoot -ChildPath $script:projectName)

        @'
namespace NuGetPack
{
    public sealed class NoOp
    {
    }
}
'@ | Set-Content -Path (Join-Path -Path $script:testRoot -ChildPath 'NoOp.cs')

        # Make sure output directory gets created by the task
        $whiskeyYmlPath = Join-Path -Path $script:testRoot -ChildPath 'whiskey.yml'
        @'
Build:
- Version:
    Version: 0.0.0
- MSBuild:
    Path: NuGetPack.csproj
'@ | Set-Content -Path $whiskeyYmlPath

        $propertyArg = @{}
        if( $InReleaseMode )
        {
            $propertyArg['Property'] = 'Configuration=Release'
        }

        Initialize-WhiskeyTestPSModule -Name 'VSSetup' -BuildRoot $script:testRoot
        $script:context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath $whiskeyYmlPath
        if( $InReleaseMode )
        {
            $script:context.RunBy = [Whiskey.RunBy]::BuildServer
        }
        else
        {
            $script:context.RunBy = [Whiskey.RunBy]::Developer
        }
        Invoke-WhiskeyBuild -Context $script:context | Out-String | Write-WhiskeyVerbose
        Reset-WhiskeyTestPSModule
    }

    function GivenFile
    {
        param(
            $Name,
            $Content
        )

        $Content | Set-Content -Path (Join-Path -Path $script:testRoot -ChildPath $Name)
    }

    function GivenRunByBuildServer
    {
        $script:byBuildServer = $true
    }

    function GivenPath
    {
        param(
            [String[]]$Path
        )

        $script:path = $Path
    }

    function GivenNoPath
    {
        $script:path = $null
    }

    function GivenVersion
    {
        param(
            $script:version
        )

        $script:version = $script:version
    }

    function WhenRunningNuGetPackTask
    {
        [CmdletBinding()]
        param(
            [switch]$Symbols,

            $Property,

            $ID,

            $PackageVersion
        )

        $byItDepends = @{}
        if( $script:byBuildServer )
        {
            $byItDepends['ForBuildServer'] = $true
        }
        else
        {
            $byItDepends['ForDeveloper'] = $true
        }

        $script:context = New-WhiskeyTestContext -ForVersion '1.2.3+buildstuff' -ForBuildRoot $script:testRoot @byItDepends

        Get-ChildItem -Path $script:context.OutputDirectory | Remove-Item -Recurse -Force

        $taskParameter = @{ }

        if( $path )
        {
            $taskParameter['Path'] = $path
        }

        if( $Symbols )
        {
            $taskParameter['Symbols'] = $true
        }

        if( $script:version )
        {
            $taskParameter['Version'] = $script:version
        }

        if( $Property )
        {
            $taskParameter['Properties'] = $Property
        }

        if( $PackageVersion )
        {
            $taskParameter['PackageVersion'] = $PackageVersion
        }

        if( $ID )
        {
            $taskParameter['PackageID'] = $ID
        }

        $script:threwException = $false
        try
        {
            $Global:error.Clear()
            Invoke-WhiskeyTask -TaskContext $script:context -Parameter $taskParameter -Name 'NuGetPack'
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }

    function ThenFile
    {
        param(
            $InPackage,
            $FileName,
            $Is
        )

        $packagePath = Join-Path -Path $script:testRoot -ChildPath '.output'
        $packagePath = Join-Path -Path $packagePath -ChildPath $InPackage

        $extractDir = Join-Path -Path $script:testRoot -ChildPath '.output\extracted'
        [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractDir)

        Get-Content -Path (Join-Path -Path $extractDir -ChildPath $FileName) -Raw | Should -Be $Is
    }

    function ThenSpecificNuGetVersionInstalled
    {
        $nugetVersion = 'NuGet.CommandLine.{0}' -f $script:version

        Join-Path -Path $script:context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
    }

    function ThenTaskThrowsAnException
    {
        param(
            $ExpectedErrorMessage
        )

        $script:threwException | Should -BeTrue

        $Global:Error | Should -Not -BeNullOrEmpty
        $lastError = $Global:Error[0]
        $lastError | Should -Match $ExpectedErrorMessage
    }

    function ThenTaskSucceeds
    {
        $script:threwException | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenPackageCreated
    {
        param(
            $Name = 'NuGetPack',

            $Version = $script:context.Version.SemVer1,

            [switch]$Symbols
        )

        $symbolsPath =
             Join-Path -Path $script:Context.OutputDirectory -ChildPath ('{0}.{1}.symbols.nupkg' -f $Name,$Version)
        $nonSymbolsPath =
            Join-Path -Path $script:Context.OutputDirectory -ChildPath ('{0}.{1}.nupkg' -f $Name,$Version)
        if( $Symbols )
        {
            $symbolsPath | Should -Exist
            $nonSymbolsPath | Should -Exist
        }
        else
        {
            $nonSymbolsPath | Should -Exist
            $symbolsPath | Should -Not -Exist
        }
    }

    function ThenPackageNotCreated
    {
        (Join-Path -Path $script:context.OutputDirectory -ChildPath '*.nupkg') | Should -Not -Exist
    }
}

Describe 'NuGetPack' {
    BeforeEach {
        $script:nugetUri = 'https://nuget.org'
        $script:apiKey = 'fubar:snafu'
        $script:publishFails = $false
        $script:packageExistsCheckFails = $false
        $script:path = $script:projectName
        $script:byBuildServer = $false
        $script:version = $null
        $script:testRoot = New-WhiskeyTestRoot
     }

    It 'should fail' {
        GivenABuiltLibrary
        GivenPath -Path 'I\do\not\exist.csproj'
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskThrowsAnException 'does not exist'
    }

    It 'should create package' {
        GivenABuiltLibrary
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackageCreated
    }

    It 'should include symbols in the package' {
        GivenABuiltLibrary
        WhenRunningNuGetPackTask -Symbols
        ThenTaskSucceeds
        ThenPackageCreated -Symbols
    }

    It 'create release mode package' {
        GivenABuiltLibrary -InReleaseMode
        GivenRunByBuildServer
        WhenRunningNugetPackTask
        ThenTaskSucceeds
        ThenPackageCreated
    }

    It 'should create multiple packages' {
        GivenABuiltLibrary
        GivenPath @( $script:projectName, $script:projectName )
        WhenRunningNugetPackTask
        ThenPackageCreated
        ThenTaskSucceeds
    }

    It 'should use custom version of NuGet' {
        GivenABuiltLibrary
        GivenVersion '5.9.3'
        WhenRunningNuGetPackTask
        ThenSpecificNuGetVersionInstalled
        ThenTaskSucceeds
        ThenPackageCreated
    }

    It 'should create package from nuspec file' {
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package>
    <metadata>
        <id>package</id>
        <version>$Version$</version>
        <authors>$Authors$</authors>
        <description>$Description$</description>
    </metadata>
</package>
'@
        GivenPath 'package.nuspec'
        WhenRunningNuGetPackTask -Property @{ 'Version' = 'Snafu Version'; 'Authors' = 'Fizz Author' ; 'Description' = 'Buzz Desc' }
        ThenPackageCreated 'package'
        ThenFile 'package.nuspec' -InPackage 'package.1.2.3.nupkg' -Is @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>package</id>
    <version>1.2.3</version>
    <authors>Fizz Author</authors>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Buzz Desc</description>
  </metadata>
</package>
"@
        }

    It 'should use ID in nuspec file' {
        GivenFile 'FileName.nuspec' @'
<?xml version="1.0"?>
<package>
    <metadata>
        <id>ID</id>
        <title>Title</title>
        <version>9.9.9</version>
        <authors>Somebody</authors>
        <description>Description</description>
    </metadata>
</package>
'@
        GivenPath 'FileName.nuspec'
        WhenRunningNuGetPackTask -ID 'ID'
        ThenPackageCreated 'ID'
        ThenFile 'ID.nuspec' -InPackage 'ID.1.2.3.nupkg' -Is @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>ID</id>
    <version>1.2.3</version>
    <title>Title</title>
    <authors>Somebody</authors>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Description</description>
  </metadata>
</package>
"@
    }

    It 'should customize package version' {
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package>
  <metadata>
    <id>package</id>
    <version>9.9.9</version>
    <authors>Somebody</authors>
    <description>Description</description>
  </metadata>
</package>
'@
        GivenPath 'package.nuspec'
        WhenRunningNuGetPackTask -PackageVersion '2.2.2'
        ThenPackageCreated 'package' -Version '2.2.2'
        ThenFile 'package.nuspec' -InPackage 'package.2.2.2.nupkg' -Is @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>package</id>
    <version>2.2.2</version>
    <authors>Somebody</authors>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Description</description>
  </metadata>
</package>
"@
    }

    It 'should validate properties' {
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package >
    <metadata>
        <id>package</id>
        <version>$script:Version$</version>
        <authors>$Authors$</authors>
        <description>$Description$</description>
    </metadata>
</package>
'@
        GivenPath 'package.nuspec'
        WhenRunningNuGetPackTask -Property 'Fubar' -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskThrowsAnException 'Property\ is\ invalid'
    }
}
