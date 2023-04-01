
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    [Whiskey.Context]$script:context = $null
    $script:property = $null
    $script:failed = $false
    $script:branch = $null
    $script:initialVersion = $null
    $script:testNum = 0
    $script:versions = @()

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
            $script:property
        )

        $script:property = $script:property
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

    function GivenUniversalPackageVersions
    {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyArray()]
            [String[]] $Version
        )

        $script:versions = $Version
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

        $script:context.Version.SemVer2.ToString() | Should -Be $ExpectedVersion.ToString()
        $ExpectedVersion = New-Object 'SemVersion.SemanticVersion' ($ExpectedVersion.Major,$ExpectedVersion.Minor,$ExpectedVersion.Patch,$ExpectedVersion.Prerelease)
        $script:context.Version.SemVer2NoBuildMetadata.ToString() | Should -Be $ExpectedVersion.ToString()
    }

    function ThenSemVer1Is
    {
        param(
            [SemVersion.SemanticVersion]$ExpectedVersion
        )

        $script:context.Version.SemVer1.ToString() | Should -Be $ExpectedVersion.ToString()
    }

    function ThenTaskFailed
    {
        $script:failed | Should -Be $true
    }

    function ThenVersionIs
    {
        param(
            [Version]$ExpectedVersion
        )

        $script:context.Version.Version | Should -Be $ExpectedVersion
    }

    function WhenRunningTask
    {
        [CmdletBinding(DefaultParameterSetName='NotUPack')]
        param(
            [switch]$AsDeveloper,

            [String]$WithYaml,

            [Parameter(Mandatory, ParameterSetName='UPack')]
            [String] $ForUniversalPackage,

            [Parameter(Mandatory, ParameterSetName='UPack')]
            [String] $At,

            [Parameter(Mandatory, ParameterSetName='UPack')]
            [String[]] $WithVersions
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
            $script:property = $script:context.Configuration['Build'][0]['Version']
        }
        else
        {
            $script:context = New-WhiskeyTestContext @forParam
        }

        $script:context.Version = $script:initialVersion
        if( $script:branch )
        {
            $script:context.BuildMetadata.ScmBranch = $script:branch
        }

        if( $sourceBranch )
        {
            $script:context.BuildMetadata.ScmSourceBranch = $sourceBranch
            $script:context.BuildMetadata.IsPullRequest = $true
        }

        if( $ForUniversalPackage )
        {
            $script:versions = $WithVersions
            $pkgFeedUrl = "$($At)/packages?name=$($ForUniversalPackage)"
            Mock -CommandName 'Invoke-RestMethod' `
                 -ModuleName 'Whiskey' `
                 -ParameterFilter { $Uri -Eq $pkgFeedUrl } `
                 -MockWith { return [pscustomobject]@{ versions = $script:versions } } #.GetNewClosure()
        }

        $Global:Error.Clear()
        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context `
                               -Name 'Version' `
                               -Parameter $script:property `
                               -InformationAction SilentlyContinue
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_

        }
    }
}

Describe 'Version' {
    BeforeEach {
        $script:context = $null
        $script:version = $null
        $script:failed = $false
        $script:branch = $null
        $script:sourceBranch = $null
        $script:versions = @()
        $script:initialVersion = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyVersionObject' `
                                                                -Parameter @{ 'SemVer' = '0.0.0' }
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        if( -not (Test-Path -Path $script:testRoot) )
        {
            New-Item -Path $script:testRoot -ItemType 'Directory'
        }
    }

    It 'should use YAML node value as version' {
        GivenProperty @{ '' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask
        ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }

    It 'should not use build metadata' {
        GivenProperty @{ '' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask -AsDeveloper
        ThenSemVer2Is '4.4.5-rc.5'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }

    It 'should use the version property value as the version' {
        GivenProperty @{ 'Version' = '4.4.5-rc.5+branch.deadbee' }
        WhenRunningTask
        ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
        ThenSemVer1Is '4.4.5-rc5'
        ThenVersionIs '4.4.5'
    }

    It 'should fail' {
        GivenProperty @{ 'Version' = '4.5' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'is\ not\ a\ semantic\ version'
    }

    It 'should have no metadata in build version' {
        GivenProperty @{ 'Version' = '4.5.6' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }

    It 'should have no build metadata' {
        GivenProperty @{ 'Version' = '4.5.6-rc.5' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6-rc.5'
        ThenSemVer1Is '4.5.6-rc5'
        ThenVersionIs '4.5.6'
    }

    It 'should not have prerelease in the version' {
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6+branch.commit'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }

    It 'should use prerelease property value for prerelease' {
        GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = 'rc.2' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6-rc.2'
        ThenSemVer1Is '4.5.6-rc2'
        ThenVersionIs '4.5.6'
    }

    It 'should fail' {
        GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = '~!@#$%^&*()_+' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'not\ a\ valid\ prerelease\ version'
    }

    It 'should use build property as build metadata' {
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = 'branch2.commit2' }
        WhenRunningTask
        ThenSemVer2Is '4.5.6+branch2.commit2'
        ThenSemVer1Is '4.5.6'
        ThenVersionIs '4.5.6'
    }

    It 'should convert to valid value' {
        GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = 'feature/fubar-snafu.deadbee' }
        WhenRunningTask
        ThenVersionIs '4.5.6'
        ThenSemVer1Is '4.5.6'
        ThenSemVer2Is '4.5.6+feature-fubar-snafu.deadbee'
    }

    It 'should set version from PowerShell module manifest' {
        GivenFile 'manifest.psd1' '@{ ModuleVersion = ''4.2.3'' }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3'
        ThenSemVer2Is '4.2.3'
    }

    It 'should fail when version is missing from PowerShell module manifest' {
        GivenFile 'manifest.psd1' '@{ }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'is\ invalid\ or\ doesn''t contain\ a\ "ModuleVersion"\ property'
    }

    It 'should fail when version in PowerShell module manifest is invalid' {
        GivenFile 'manifest.psd1' '@{ ModuleVersion = ''4.2'' }'
        GivenProperty @{ Path = 'manifest.psd1' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'Powershell\ module\ manifest'
    }

    It 'should use prerelease version from the PowerShell Gallery' {
        GivenFile 'Whiskey.psd1' '@{ ModuleVersion = ''0.41.1'' ; PrivateData = @{ PSData = @{ Prerelease = ''beta.1'' } } }'
        GivenProperty @{ Path = 'Whiskey.psd1' }
        WhenRunningTask
        ThenVersionIs '0.41.1'
        ThenSemVer1Is '0.41.1-beta1035'
        ThenSemVer2Is '0.41.1-beta.1035' # The last beta version was 0.41.1-beta1034, so next one should be beta1035.
    }

    It 'should read version from packageJson file' {
        GivenFile 'package.json' '{ "Version": "4.2.3-rc.1" }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3-rc1'
        ThenSemVer2Is '4.2.3-rc.1'
    }

    It 'should get latest version from NPM registry' {
        Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNode' `
                                     -Parameter @{ InstallRootPath = $testRoot ; OutFileRootPath = $testRoot }
        GivenFile 'package.json' '{ "name": "react-native", "version": "0.68.0-rc.0" }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask
        ThenVersionIs '0.68.0'
        ThenSemVer1Is '0.68.0-rc5'
        ThenSemVer2Is '0.68.0-rc.5'
    }

    It 'should fail if version in packageJson file is missing' {
        GivenFile 'package.json' '{ }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs '"Version"\ property\ is\ missing'
    }

    It 'should fail if packageJson file is invalid JSON' {
        GivenFile 'package.json' '{ "Version" =  }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        $Global:Error.RemoveAt($Global:Error.Count -1)
        ThenErrorIs 'package\.json"\ contains\ invalid\ JSON'
    }

    It 'should fail when version in pakageJson is inalid' {
        GivenFile 'package.json' '{ "Version": "4.2"  }'
        GivenProperty @{ Path = 'package.json' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'from\ Node\ package\.json'
    }

    It 'should read version from csproj file' {
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

    It 'should use next prerelease version based on what is in NuGet' {
        GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Version>3.0.0-beta-0</Version>
    <PackageId>NUnit</PackageId>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask
        ThenVersionIs '3.0.0'
        if( Get-PackageSource -ProviderName 'NuGet' )
        {
            ThenSemVer1Is '3.0.0-beta6'
            ThenSemVer2Is '3.0.0-beta-6'
        }
        else
        {
            ThenSemVer1Is '3.0.0-beta0'
            ThenSemVer2Is '3.0.0-beta-0'
        }
    }

    It 'should use next prerelease version based on what is in NuGet' {
        GivenProperty @{ Version = '3.0.0-alpha-0' ; NuGetPackageID = 'NUnit' }
        WhenRunningTask
        ThenVersionIs '3.0.0'
        if( Get-PackageSource -ProviderName 'NuGet' )
        {
            ThenSemVer1Is '3.0.0-alpha6'
            ThenSemVer2Is '3.0.0-alpha-6'
        }
        else
        {
            ThenSemVer1Is '3.0.0-alpha0'
            ThenSemVer2Is '3.0.0-alpha-0'
        }
    }

    It 'should read from from csproj file that has an XML namespace' {
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

    It 'should fail when version in csproj file is missing' {
     GivenFile 'lib.csproj' @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
  </PropertyGroup>
</Project>
'@
        GivenProperty @{ Path = 'lib.csproj' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'element\ "/Project/PropertyGroup/Version"\ does\ not\ exist'
    }

    It 'should fail when csproj file contains invalid XML' {
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

    It 'should fail when version in csproj file is invalid' {
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
        ThenErrorIs '\.csproj\ file'
    }

    It 'should use version information from YAML over version information in another file' {
        GivenFile 'package.json' '{ "Version": "4.2.3-rc.1+fubar.snafu" }'
        GivenProperty @{ Path = 'package.json' ; Prerelease = 'rc.5' ; Build = 'fizz.buzz' }
        WhenRunningTask
        ThenVersionIs '4.2.3'
        ThenSemVer1Is '4.2.3-rc5'
        ThenSemVer2Is '4.2.3-rc.5+fizz.buzz'
    }

    Context 'by developer' {
        It 'should not set prerelease metadata' {
                GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            WhenRunningTask
            ThenVersionIs '1.2.3'
            ThenSemVer1Is '1.2.3'
            ThenSemVer2Is '1.2.3'
        }
    }
    Context 'by build server' {
        It 'should set prerelease metadata' {
                GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            GivenBranch 'beta/some-feature'
            WhenRunningTask
            ThenVersionIs '1.2.3'
            ThenSemVer1Is '1.2.3-beta2'
            ThenSemVer2Is '1.2.3-beta.2'
        }
    }

    Context 'by developer' {
        It 'should not set prerelease metadata' {
                GivenFile 'Whiskey.psd1' '@{ ModuleVersion = ''0.41.1'' }'
            GivenProperty @{ 'Path' = 'Whiskey.psd1'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            WhenRunningTask
            ThenVersionIs '0.41.1'
            ThenSemVer1Is '0.41.1'
            ThenSemVer2Is '0.41.1'
        }
    }
    Context 'by build server' {
        It 'should set prerelease metadata' {
                GivenFile 'Whiskey.psd1' '@{ ModuleVersion = ''0.41.1'' }'
            GivenProperty @{ 'Path' = 'Whiskey.psd1'; Prerelease = @( @{ 'alpha/*' = 'alpha.1' } ), @( @{ 'beta/*' = 'beta.2' } ) }
            GivenBranch 'beta/some-feature'
            WhenRunningTask
            ThenVersionIs '0.41.1'
            ThenSemVer1Is '0.41.1-beta1035'
            ThenSemVer2Is '0.41.1-beta.1035'
        }
    }

    It 'should use prerelease for a specific branch' {
        GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @{ 'alpha/*' = 'alpha.1'; 'beta/*' = 'beta.2' } }
        GivenBranch 'beta/fubar'
        WhenRunningTask
        ThenVersionIs '1.2.3'
        ThenSemVer1Is '1.2.3-beta2'
        ThenSemVer2Is '1.2.3-beta.2'
    }

    It 'should use the correct prerelease when there are different ids for different branches' {
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

    It 'should fail when prerelease map is not a map' {
        GivenProperty @{ 'Version' = '1.2.3'; Prerelease = @( 'alpha/*' ) }
        GivenBranch 'beta/fubar'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs 'unable\ to\ find\ keys'
    }

    It 'should allow prerelease property to be a prerelease label' {
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Prerelease' = 'alpha' }
        WhenRunningTask
        ThenVersionIs '0.0.0'
        ThenSemVer1Is '0.0.0-alpha'
        ThenSemVer2Is '0.0.0-alpha+build'
    }

    It 'should only set build metadata on the current version' {
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Build' = 'fubar' }
        WhenRunningTask
        ThenVersionIs '0.0.0'
        ThenSemVer1Is '0.0.0-prerelease'
        ThenSemVer2Is '0.0.0-prerelease+fubar'
    }

    It 'should ignore prerelese and build metadata if only setting version' {
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenProperty @{ 'Version' = '1.1.1' }
        WhenRunningTask
        ThenVersionIs '1.1.1'
        ThenSemVer1Is '1.1.1'
        ThenSemVer2Is '1.1.1'
    }

    It 'should overwrite prerelease and build metadata if reading from from an external file' {
        GivenCurrentVersion '0.0.0-prerelease+build'
        GivenFile 'package.json' '{ "Version": "1.1.1" }'
        GivenProperty @{ Path = 'package.json' ; }
        WhenRunningTask
        ThenVersionIs '1.1.1'
        ThenSemVer1Is '1.1.1'
        ThenSemVer2Is '1.1.1'
    }

    It 'should read version from a Chef cookbook metadataRb file' {
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

    It 'should fail when Chef cookbook metadataRb file does not have a version property' {
        GivenFile 'metadata.rb' @'
name 'cookbook_name'
description 'Installs/Configures cookbook_name'
'@
        GivenProperty @{ Path = 'metadata.rb' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenErrorIs ([regex]::Escape('Unable to locate property "version ''x.x.x''" in metadata.rb file'))
    }

    It 'should use source branch name for prerelease branch matching when building a pull request' {
        GivenCurrentVersion '1.0.0'
        GivenBranch 'one'
        GivenSourceBranch 'two'
        GivenProperty @{ 'Prerelease' = @( @{ 'one' = 'one' }, @{ 'two' = 'two' } ) }
        WhenRunningTask
        ThenVersionIs '1.0.0'
        ThenSemVer1Is '1.0.0-two'
        ThenSemVer2Is '1.0.0-two'

    }

    It 'should use next version number for same version' {
        GivenCurrentVersion '1.0.0-rc.0'
        GivenProperty @{ UPackName = 'Fu bar' ; UPackFeedUrl = 'https://example.com/upack/Apps' }
        WhenRunningTask -ForUniversalPackage 'Fu bar' -At 'https://example.com/upack/Apps' -WithVersions @(
                '1.1.0',
                '1.0.0',
                '1.0.0-rc.5',
                '1.0.0-rc.4',
                '1.0.0-rc.3',
                '1.0.0-rc.2',
                '1.0.0-rc.1',
                '1.0.0-alpha.1'
            )
        ThenVersionIs '1.0.0'
        ThenSemVer1Is '1.0.0-rc6'
        ThenSemVer2Is '1.0.0-rc.6'
    }

    It 'should use same version for unpublished package' {
        Mock -CommandName 'Invoke-RestMethod' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Uri -Eq "https://example.com/upack/Apps/packages?name=snafu" } `
             -MockWith { Invoke-WebRequest -Uri 'https://httpstat.us/404' }
        GivenCurrentVersion '1.0.0-rc.1'
        GivenProperty @{ UPackName = 'snafu' ; UPackFeedUrl = 'https://example.com/upack/Apps' }
        WhenRunningTask
        ThenVersionIs '1.0.0'
        ThenSemVer1Is '1.0.0-rc1'
        ThenSemVer2Is '1.0.0-rc.1'
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'should increment patch based on last published package' {
        GivenCurrentVersion '22.517.0'
        GivenProperty @{
            IncrementPatchVersion = $true;
            UPackName = 'patch';
            UPackFeedUrl = 'https://example.com/upack/Apps'
        }
        WhenRunningTask -ForUniversalPackage 'patch' -At 'https://example.com/upack/Apps' -WithVersions @(
            '22.518.0',
            '22.517.3',
            '22.517.2',
            '22.517.1',
            '22.517.0',
            '22.516.22'
        )
        ThenVersionIs '22.517.4'
        ThenSemVer1Is '22.517.4'
        ThenSemVer2Is '22.517.4'
    }

    # Make sure the patch number gets set *first* so any prerelease info gets set correctly.
    It 'should set prerelease to 1' {
        GivenCurrentVersion '22.518.7-rc.4'
        GivenProperty @{
            IncrementPatchVersion = $true;
            UPackName = 'patch';
            UPackFeedUrl = 'https://example.com/upack/Apps'
        }
        WhenRunningTask -ForUniversalPackage 'patch' -At 'https://example.com/upack/Apps' -WithVersions @(
            '22.5187.7-rc.3',
            '22.518.7-rc.2',
            '22.518.7-rc.1'
        )
        ThenVersionIs '22.518.8'
        ThenSemVer1Is '22.518.8-rc1'
        ThenSemVer2Is '22.518.8-rc.1'
    }
}