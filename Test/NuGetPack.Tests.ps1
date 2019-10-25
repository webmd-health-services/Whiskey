
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestModule 'VSSetup'

$testRoot = $null
$projectName = 'NuGetPack.csproj'
$context = $null
$nugetUri = $null
$apiKey = $null
$publishFails = $false
$packageExistsCheckFails = $false
$threwException = $false
$byBuildServer = $false
$version = $null

function InitTest
{
    param(
    )

    $script:nugetUri = 'https://nuget.org'
    $script:apiKey = 'fubar:snafu'
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:path = $projectName
    $script:byBuildServer = $false
    $script:version = $null

    $script:testRoot = New-WhiskeyTestRoot
}

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
'@ | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $projectName)

    @'
namespace NuGetPack
{
    public sealed class NoOp
    {
    }
}
'@ | Set-Content -Path (Join-Path -Path $testRoot -ChildPath 'NoOp.cs')

    # Make sure output directory gets created by the task
    $whiskeyYmlPath = Join-Path -Path $testRoot -ChildPath 'whiskey.yml'
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

    Initialize-WhiskeyTestPSModule -Name 'VSSetup' -BuildRoot $testRoot
    $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath $whiskeyYmlPath 
    if( $InReleaseMode )
    {
        $context.RunBy = [Whiskey.RunBy]::BuildServer
    }
    else
    {
        $context.RunBy = [Whiskey.RunBy]::Developer
    }
    Invoke-WhiskeyBuild -Context $context |
        Out-String |
        Write-Verbose
    Reset-WhiskeyTestPSModule
}

function GivenFile
{
    param(
        $Name,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $Name) 
}

function GivenRunByBuildServer
{
    $script:byBuildServer = $true
}

function GivenPath
{
    param(
        [string[]]$Path
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
        $version
    )
    
    $script:version = $version
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
    if( $byBuildServer )
    {
        $byItDepends['ForBuildServer'] = $true
    }
    else
    {
        $byItDepends['ForDeveloper'] = $true
    }
            
    $script:context = New-WhiskeyTestContext -ForVersion '1.2.3+buildstuff' -ForBuildRoot $testRoot @byItDepends
    
    Get-ChildItem -Path $context.OutputDirectory | Remove-Item -Recurse -Force

    $taskParameter = @{ }

    if( $path )
    {
        $taskParameter['Path'] = $path
    }

    if( $Symbols )
    {
        $taskParameter['Symbols'] = $true
    }
    
    if( $version )
    {
        $taskParameter['Version'] = $version
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

    $optionalParams = @{ }
    $script:threwException = $false
    try
    {
        $Global:error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NuGetPack'
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

    $packagePath = Join-Path -Path $testRoot -ChildPath '.output'
    $packagePath = Join-Path -Path $packagePath -ChildPath $InPackage

    $extractDir = Join-Path -Path $testRoot -ChildPath '.output\extracted'
    [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractDir)

    Get-Content -Path (Join-Path -Path $extractDir -ChildPath $FileName) -Raw | Should -Be $Is
}

function ThenSpecificNuGetVersionInstalled
{
    $nugetVersion = 'NuGet.CommandLine.{0}' -f $version

    Join-Path -Path $context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
}

function ThenTaskThrowsAnException
{
    param(
        $ExpectedErrorMessage
    )

    $threwException | Should Be $true

    $Global:Error | Should Not BeNullOrEmpty
    $lastError = $Global:Error[0]
    $lastError | Should -Match $ExpectedErrorMessage
}

function ThenTaskSucceeds
{
    $threwException | Should Be $false
    $Global:Error | Should BeNullOrEmpty
}

function ThenPackageCreated
{
    param(
        $Name = 'NuGetPack',

        $Version = $context.Version.SemVer1,

        [switch]$Symbols
    )

    $symbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('{0}.{1}.symbols.nupkg' -f $Name,$Version)
    $nonSymbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('{0}.{1}.nupkg' -f $Name,$Version)
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
    (Join-Path -Path $context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
}

if( -not $IsWindows )
{
    Describe 'NuGetPack.when run on non-Windows platform' {
        It 'should fail' {
            InitTest
            WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
            ThenTaskThrowsAnException 'Windows\ platform'
        }
    }
    return
}

Describe 'NuGetPack.when creating a NuGet package with an invalid project' {
    It 'should fail' {
        InitTest
        GivenABuiltLibrary
        GivenPath -Path 'I\do\not\exist.csproj'
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskThrowsAnException 'does not exist'
    }
}

Describe 'NuGetPack.when creating a NuGet package' {
    It 'should create the package' {
        InitTest
        GivenABuiltLibrary
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackageCreated
    }
}

Describe 'NuGetPack.when creating a symbols NuGet package' {
    It 'should include symbols in the package' {
        InitTest
        GivenABuiltLibrary
        WhenRunningNuGetPackTask -Symbols
        ThenTaskSucceeds
        ThenPackageCreated -Symbols
    }
}

Describe 'NuGetPack.when creating a package built in release mode' {
    It 'create the package' {
        InitTest
        GivenABuiltLibrary -InReleaseMode
        GivenRunByBuildServer
        WhenRunningNugetPackTask
        ThenTaskSucceeds
        ThenPackageCreated
    }
}

Describe 'NuGetPack.when creating multiple packages for publishing' {
    It 'should create all the packages' {
        InitTest
        GivenABuiltLibrary
        GivenPath @( $projectName, $projectName )
        WhenRunningNugetPackTask 
        ThenPackageCreated
        ThenTaskSucceeds
    }
}
Describe 'NuGetPack.when creating a package using a specifc version of NuGet' {
    It 'should download and use that version of NuGet' {
        InitTest
        GivenABuiltLibrary
        GivenVersion '3.5.0'
        WhenRunningNuGetPackTask
        ThenSpecificNuGetVersionInstalled
        ThenTaskSucceeds
        ThenPackageCreated
    }
}

Describe 'NuGetPack.when creating package from .nuspec file' {
    It 'should create the package' {
        InitTest
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package >
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
    <owners>Fizz Author</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Buzz Desc</description>
  </metadata>
</package>
"@
    }
}

Describe 'NuGetPack.when package ID is different than path' {
    It 'should leave the ID alone' {
        InitTest
        GivenFile 'FileName.nuspec' @'
<?xml version="1.0"?>
<package >
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
    <owners>Somebody</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Description</description>
  </metadata>
</package>
"@
    }
}

Describe 'NuGetPack.when customizing version' {
    It 'should change the version in the .nuspec file' {
        InitTest
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package >
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
    <owners>Somebody</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Description</description>
  </metadata>
</package>
"@
    }
}

Describe 'NuGetPack.when Properties property is invalid' {
    It 'should fail' {
        InitTest
        GivenFile 'package.nuspec' @'
<?xml version="1.0"?>
<package >
  <metadata>
    <id>package</id>
    <version>$Version$</version>
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