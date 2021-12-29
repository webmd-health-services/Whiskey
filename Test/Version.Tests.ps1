
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null
$property = $null
$failed = $false
$branch = $null
$initialVersion = $null
$testNum = 0

function Init
{
    $script:context = $null
    $script:version = $null
    $script:failed = $false
    $script:branch = $null
    $script:sourceBranch = $null
    $script:initialVersion = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyVersionObject' `
                                                          -Parameter @{ 'SemVer' = '0.0.0' }
    $script:testRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($testNum++)
    if( -not (Test-Path -Path $script:testRoot) )
    {
        New-Item -Path $script:testRoot -ItemType 'Directory'
    }
}

function GivenFile
{
    param(
        $Name,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $script:testRoot -ChildPath $Name)
}

function GivenProperty
{
    param(
        $Property
    )

    $script:property = $Property
}

function GivenBranch
{
    param(
        [String] $Named
    )

    $script:branch = $Named
}

function GivenSourceBranch
{
    param(
        [String] $Named
    )

    $script:sourceBranch = $Named
}

function ThenErrorIs
{
    param(
        $Regex
    )

    $Global:Error | Should -Match $Regex
}

function GivenCurrentVersion
{
    param(
        $Version
    )

    $script:initialVersion = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyVersionObject' `
                                                          -Parameter @{ 'SemVer' = $Version }
}

function ThenSemVer2Is
{
    param(
        [SemVersion.SemanticVersion]$ExpectedVersion
    )

    $context.Version.SemVer2.ToString() | Should -Be $ExpectedVersion.ToString()
    $ExpectedVersion = New-Object 'SemVersion.SemanticVersion' ($ExpectedVersion.Major,$ExpectedVersion.Minor,$ExpectedVersion.Patch,$ExpectedVersion.Prerelease)
    $context.Version.SemVer2NoBuildMetadata.ToString() | Should -Be $ExpectedVersion.ToString()
}

function ThenSemVer1Is
{
    param(
        [SemVersion.SemanticVersion]$ExpectedVersion
    )

    $context.Version.SemVer1.ToString() | Should -Be $ExpectedVersion.ToString()
}

function ThenTaskFailed
{
    $failed | Should -Be $true
}

function ThenVersionIs
{
    param(
        [Version]$ExpectedVersion
    )

    $context.Version.Version | Should -Be $ExpectedVersion
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [switch]$AsDeveloper,

        [String]$WithYaml
    )

    $forParam = @{ ForBuildServer = $true }
    if( $AsDeveloper )
    {
        $forParam = @{ ForDeveloper = $true }
    }
    $forParam['ForBuildRoot'] = $script:testRoot

    if( $WithYaml )
    {
        $script:context = New-WhiskeyTestContext -ForYaml $WithYaml @forParam
        $script:property = $context.Configuration['Build'][0]['Version']
    }
    else
    {
        $script:context = New-WhiskeyTestContext @forParam
    }

    $context.Version = $initialVersion
    if( $branch )
    {
        $context.BuildMetadata.ScmBranch = $branch
    }

    if( $sourceBranch )
    {
        $context.BuildMetadata.ScmSourceBranch = $sourceBranch
        $context.BuildMetadata.IsPullRequest = $true
    }

    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyTask -TaskContext $context `
                           -Name 'Version' `
                           -Parameter $property `
                           -InformationAction SilentlyContinue
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_

    }
}

Describe 'Version.when using simplified syntax' {
    It 'should use YAML node value as version' {
        Init
        GivenProperty @{ '' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask
        ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }
}

Describe 'Version.when running as a developer' {
    It 'should not use build metadata' {
        Init
        GivenProperty @{ '' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask -AsDeveloper
        ThenSemVer2Is '4.4.5-rc.5'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }
}

Describe 'Version.when using Version property' {
    It 'should use the version property value as the version' {
        Init
        GivenProperty @{ 'Version' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask
        ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }
}

Describe 'Version.when Version is invalid' {
    It 'should fail' {
        Init
        GivenProperty @{ 'Version' = '4.5' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'is\ not\ a\ semantic\ version'
    }
}

Describe 'Version.when Version has no metadata' {
    It 'should have no metadata in build version' {
        Init
        GivenProperty @{ 'Version' = '4.5.6' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }
}

Describe 'Version.when Version has no build metadata' {
    It 'should have no build metadata' {
        Init
        GivenProperty @{ 'Version' = '4.5.6-rc.5' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6-rc.5'
        ThenSemVer1Is '4.5.6-rc5'
        ThenVersionIs '4.5.6'
    }
}

Describe 'Version.when Version has no prerelease version' {
    It 'should not have prerelease in the version' {
        Init
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6+branch.commit'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }
}

Describe 'Version.when using Prerelease property to set prerelease version' {
    It 'should use prerelease property value for prerelease' {
        Init
        GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = 'rc.2' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6-rc.2'
        ThenSemVer1Is '4.5.6-rc2'
        ThenVersionIs '4.5.6'
    }
}

Describe 'Version.when Prerelease property is not a valid prerelease version' {
    It 'should fail' {
        Init
        GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = '~!@#$%^&*()_+' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'not\ a\ valid\ prerelease\ version'
    }
}

Describe 'Version.when using Build property to set build metadata' {
    It 'should use build propertyas build metadata' {
        Init
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = 'branch2.commit2' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6+branch2.commit2'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }
}

Describe 'Version.when Build property is not a valid build metadata' {
    It 'should convert to valid value' {
        Init
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = 'feature/fubar-snafu.deadbee' }
        WhenRunningTask
        ThenVersionIs '4.5.6'
        ThenSemVer1Is '4.5.6'
        ThenSemVer2Is '4.5.6+feature-fubar-snafu.deadbee'
    }
}

Describe 'Version.when pulling version from PowerShell module manifest' {
    It 'should set version from PowerShell module manifest' {
        Init
        GivenFile 'manifest.psd1' '@{ ModuleVersion = ''4.2.3'' }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3'
        ThenSemVer2Is '4.2.3'
    }
}

Describe 'Version.when pulling version from PowerShell module manifest and version is missing' {
    It 'should fail when version is missing from PowerShell module manifest' {
        Init
        GivenFile 'manifest.psd1' '@{ }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'is\ invalid\ or\ doesn''t contain\ a\ ''ModuleVersion''\ property'
    }
}

Describe 'Version.when pulling version from PowerShell module manifest and version is invalid' {
    It 'should fail when version in PowerShell module manifest is invalid' {
        Init
        GivenFile 'manifest.psd1' '@{ ModuleVersion = ''4.2'' }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'Powershell\ module\ manifest'
    }
}

Describe 'Version.when pulling version from package.json' {
    It 'should read version from packageJson file' {
        Init
        GivenFile 'package.json' '{ "Version": "4.2.3-rc.1" }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3-rc1'
        ThenSemVer2Is '4.2.3-rc.1'
    }
}

Describe 'Version.when version in package.json is missing' {
    It 'should fail if version in packageJson file is missing' {
        Init
        GivenFile 'package.json' '{ }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs '''Version''\ property\ is\ missing'
    }
}

Describe 'Version.when package.json is invalid JSON' {
    It 'should fail if packageJson file is invalid JSON' {
        Init
        GivenFile 'package.json' '{ "Version" =  }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        $Global:Error.RemoveAt($Global:Error.Count -1)
        ThenErrorIs 'package\.json''\ contains\ invalid\ JSON'
    }
}

Describe 'Version.when version in package.json is invalid' {
    It 'should fail when version in packageJson is inalid' {
        Init
        GivenFile 'package.json' '{ "Version": "4.2"  }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'from\ Node\ package\.json'
    }
}

Describe 'Version.when reading version from .csproj file' {
    It 'should read version from csproj file' {
        Init
        GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Version>0.0.2</Version>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask
        ThenVersionIs '0.0.2'
        ThenSemVer1Is '0.0.2'
        ThenSemVer2Is '0.0.2'
    }
}

Describe 'Version.when reading version from .csproj file that has namespace' {
    It 'should read from from csproj file that has an XML namespace' {
        Init
        GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <Version>0.0.2</Version>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'remove\ the\ "xmlns"\ attribute'
    }
}

Describe 'Version.when version in .csproj file is missing' {
    It 'should fail when version in csproj file is missing' {
        Init
     GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'element\ ''/Project/PropertyGroup/Version''\ does\ not\ exist'
    }
}

Describe 'Version.when .csproj contains invalid XML' {
    It 'should fail when csproj file contains invalid XML' {
        Init
      GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        $Global:Error.RemoveAt($Global:Error.Count - 1)
        ThenErrorIs 'contains\ invalid\ xml'
    }
}

Describe 'Version.when version in .csproj is invalid' {
    It 'should fail when version in csproj file is invalid' {
        Init
     GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Version>4.2</Version>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs '\.NET\ \.csproj\ file'
    }
}

Describe 'Version.when file and whiskey.yml both contain build and prerelease metadata' {
    It 'should use version information from YAML over version information in another file' {
        Init
        GivenFile 'package.json' '{ "Version": "4.2.3-rc.1+fubar.snafu" }'
        GivenProperty @{ Path = 'package.json' ; Prerelease = 'rc.5' ; Build = 'fizz.buzz' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3-rc5'
        ThenSemVer2Is '4.2.3-rc.5+fizz.buzz'
    }
}

Describe 'Version.when Prerelease is a list of branch maps' {
    Context 'by developer' {
        It 'should not set prerelease metadata' {
            Init
            GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            WhenRunningTask
            ThenVersionIs '1.2.3'
            ThenSemVer1Is '1.2.3'
            ThenSemVer2Is '1.2.3'
        }
    }
    Context 'by build server' {
        It 'should set prerelease metadata' {
            Init
            GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            GivenBranch 'beta/some-feature'
            WhenRunningTask
            ThenVersionIs '1.2.3'
            ThenSemVer1Is '1.2.3-beta2'
            ThenSemVer2Is '1.2.3-beta.2'
        }
    }
}

Describe 'Version.when Prerelease is a branch map' {
    It 'should use prerelease for a specific branch' {
        Init
        GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @{ 'alpha/*' = 'alpha.1'; 'beta/*' = 'beta.2' } }
        GivenBranch 'beta/fubar'
        WhenRunningTask
        ThenVersionIs '1.2.3'
        ThenSemVer1Is '1.2.3-beta2'
        ThenSemVer2Is '1.2.3-beta.2'
    }
}

Describe 'Version.when Prerelease contains multiple matches' {
    It 'should use the correct prerelease when there are different ids for different branches' {
        Init
       GivenBranch 'feature/fubar-test'
       WhenRunningTask -WithYaml @'
Build:
- Version:
    Version: 1.2.3
    Prerelease:
    - feature/fubar-*: fubar.1
    - feature/*: alpha.1
    - develop: beta.1
'@
        ThenVersionIs '1.2.3'
        ThenSemVer1Is '1.2.3-fubar1'
        ThenSemVer2Is '1.2.3-fubar.1'
    }
}

Describe 'Version.when Prerelease branch map isn''t a map' {
    It 'should fail when prerelease map is not a map' {
        Init
        GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( 'alpha/*' ) }
        GivenBranch 'beta/fubar'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'unable\ to\ find\ keys'
    }
}

Describe 'Version.when setting just prerelease' {
    It 'should allow prerelease property to be a prerelease label' {
        Init
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Prerelease' = 'alpha' }
        WhenRunningTask
        ThenVersionIs '0.0.0'
        ThenSemVer1Is '0.0.0-alpha'
        ThenSemVer2Is '0.0.0-alpha+build'
    }
}

Describe 'Version.when setting just build' {
    It 'should only set build metadata on the current version' {
        Init
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Build' = 'fubar' }
        WhenRunningTask
        ThenVersionIs '0.0.0'
        ThenSemVer1Is '0.0.0-prerelease'
        ThenSemVer2Is '0.0.0-prerelease+fubar'
    }
}

Describe 'Version.when setting just version' {
    It 'should ignore prerelese and build metadata if only setting version' {
        Init
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Version' = '1.1.1' }
        WhenRunningTask
        ThenVersionIs '1.1.1'
        ThenSemVer1Is '1.1.1'
        ThenSemVer2Is '1.1.1'
    }
}

Describe 'Version.when setting just version from path' {
    It 'should overwrite prerelease and build metadata if reading from from an external file' {
        Init
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenFile 'package.json' '{ "Version": "1.1.1" }'
        GivenProperty @{ Path = 'package.json' ; }
        WhenRunningTask
        ThenVersionIs '1.1.1'
        ThenSemVer1Is '1.1.1'
        ThenSemVer2Is '1.1.1'
    }
}

Describe 'Version.when getting version from Chef cookbook metadata.rb file' {
    It 'should read version from a Chef cookbook metadataRb file' {
        Init
        GivenFile 'metadata.rb' @'
name 'cookbook_name'
description 'Installs/Configures cookbook_name'
# This is a comment with a similar version '2.2.2' string that shouldn't be matched
# version '9.9.9'
version '0.1.0'
chef_version '>= 12.14' if respond_to?(:chef_version)
'@
        GivenProperty @{ Path = 'metadata.rb' }
        WhenRunningTask
        ThenVersionIs '0.1.0'
        ThenSemVer1Is '0.1.0'
        ThenSemVer2Is '0.1.0'
    }
}

Describe 'Version.when Chef cookbook metadata.rb doesn''t contain a "version" property' {
    It 'should fail when Chef cookbook metadataRb file does not have a version property' {
        Init
        GivenFile 'metadata.rb' @'
name 'cookbook_name'
description 'Installs/Configures cookbook_name'
'@
        GivenProperty @{ Path = 'metadata.rb' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs ([regex]::Escape('Unable to locate property "version ''x.x.x''" in metadata.rb file'))
    }
}

Describe 'Version.when building a pull request' {
    It 'should use source branch name for prerelease branch matching when building a pull request' {
        Init
        GivenCurrentVersion '1.0.0'
        GivenBranch 'one'
        GivenSourceBranch 'two'
        GivenProperty @{ 'Prerelease' = @( @{ 'one' = 'one' }, @{ 'two' = 'two' } ) }
        WhenRunningTask
        ThenVersionIs '1.0.0'
        ThenSemVer1Is '1.0.0-two'
        ThenSemVer2Is '1.0.0-two'

    }
}