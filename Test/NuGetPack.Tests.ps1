
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Use-CallerPreference.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 
$context = $null
$nugetUri = $null
$apiKey = $null
$defaultVersion = '1.2.3'
$packageExists = $false
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
    $script:packageExists = $false
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:path = $projectName
    $script:byBuildServer = $false
    $script:version = $null
}

function GivenABuiltLibrary
{
    param(
        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $InReleaseMode
    )

    $projectRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest'
    robocopy $projectRoot $TestDrive.FullName '/MIR' '/R:0' '/MT'

    # Make sure output directory gets created by the task
    $whiskeyYmlPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'

    $project = Join-Path -Path $TestDrive.FullName -ChildPath $projectName -Resolve
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    #Get-ChildItem -Path $TestDrive.FullName -File '*.sln' | ForEach-Object { & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\NuGet.exe' -Resolve) restore $_.FullName }# $project
    $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath $whiskeyYmlPath
    if( $InReleaseMode )
    {
        $context.RunBy = [Whiskey.RunBy]::BuildServer
    }
    else
    {
        $context.RunBy = [Whiskey.RunBy]::Developer
    }
    Invoke-WhiskeyBuild -Context $context
    #Invoke-WhiskeyMSBuild -Path $project -Target 'build' @propertyArg | Write-Verbose
}

function GivenFile
{
    param(
        $Name,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name) 
}

function GivenRunByBuildServer
{
    $script:byBuildServer = $true
}

function GivenPath
{
    param(
        [string[]]
        $Path
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
        [Switch]
        $Symbols,

        $Property
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
            
    $script:context = New-WhiskeyTestContext -ForVersion '1.2.3+buildstuff' @byItDepends
    
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

    $packagePath = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $packagePath = Join-Path -Path $packagePath -ChildPath $InPackage

    $extractDir = Join-Path -Path $TestDrive.FullName -ChildPath '.output\extracted'
    [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractDir)

    It ('should have a "{0}" file' -f $FileName) {
        Get-Content -Path (Join-Path -Path $extractDir -ChildPath $FileName) -Raw | Should -Be $Is
    }
}

function ThenSpecificNuGetVersionInstalled
{
    $nugetVersion = 'NuGet.CommandLine.{0}' -f $version

    It ('should install ''{0}''' -f $nugetVersion) {
        Join-Path -Path $context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
    }
}

function ThenTaskThrowsAnException
{
    param(
        $ExpectedErrorMessage
    )

    It 'should throw an exception' {
        $threwException | Should Be $true
    }

    It ('should throw an exception that matches /{0}/' -f $ExpectedErrorMessage) {
        $Global:Error | Should Not BeNullOrEmpty
        $lastError = $Global:Error[0]
        $lastError | Should -Match $ExpectedErrorMessage
    }
}

function ThenTaskSucceeds
{
    It 'should not throw an exception' {
        $threwException | Should Be $false
        $Global:Error | Should BeNullOrEmpty
    }
}

function ThenPackageCreated
{
    param(
        $Name = 'NUnit2PassingTest',

        [Switch]
        $Symbols
    )

    $symbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('{0}.{1}.symbols.nupkg' -f $Name,$Context.Version.SemVer1)
    $nonSymbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('{0}.{1}.nupkg' -f $Name,$Context.Version.SemVer1)
    if( $Symbols )
    {
        It ('should create NuGet symbols package') {
            $symbolsPath | Should -Exist
        }

        It ('should create a non-symbols package') {
            $nonSymbolsPath | Should -Exist
        }
    }
    else
    {
        It ('should create NuGet package') {
            $nonSymbolsPath | Should -Exist
        }

        It ('should not create a symbols package') {
            $symbolsPath | Should -Not -Exist
        }
    }
 }

function ThenPackageNotCreated
{
    It 'should not create any .nupkg files' {
        (Join-Path -Path $context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'NuGetPack.when creating a NuGet package with an invalid project' {
    InitTest
    GivenABuiltLibrary
    GivenPath -Path 'I\do\not\exist.csproj'
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskThrowsAnException 'does not exist'
}

Describe 'NuGetPack.when creating a NuGet package' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackageCreated
}

Describe 'NuGetPack.when creating a symbols NuGet package' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask -Symbols
    ThenTaskSucceeds
    ThenPackageCreated -Symbols
}

Describe 'NuGetPack.when creating a package built in release mode' {
    InitTest
    GivenABuiltLibrary -InReleaseMode
    GivenRunByBuildServer
    WhenRunningNugetPackTask
    ThenTaskSucceeds
    ThenPackageCreated
}

Describe 'NuGetPack.when creating multiple packages for publishing' {
    InitTest
    GivenABuiltLibrary
    GivenPath @( $projectName, $projectName )
    WhenRunningNugetPackTask 
    ThenPackageCreated
    ThenTaskSucceeds
}

Describe 'NuGetPack.when creating a package using a specifc version of NuGet' {
    InitTest
    GivenABuiltLibrary
    GivenVersion '3.5.0'
    WhenRunningNuGetPackTask
    ThenSpecificNuGetVersionInstalled
    ThenTaskSucceeds
    ThenPackageCreated
}

Describe 'NuGetPack.when creating package from .nuspec file' {
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

Describe 'NuGetPack.when Properties property is invalid' {
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
    ThenTaskThrowsAnException 'Properties:\ Property\ is\ invalid'
}