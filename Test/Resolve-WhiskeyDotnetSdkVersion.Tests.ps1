
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$resolvedVersion = $null

function Init
{
    $Global:Error.Clear()
    $script:resolvedVersion = $null
}

function GivenReleases
{
    param(
        $Release
    )

    $releasesIndex = @{
        'releases-index' = $Release | ForEach-Object {
            @{
                'channel-version' = $_
                'releases.json'   = ('https://dotnetcli.pester.test.example.com/{0}/releases.json' -f $_)
            }
        }
    } | ConvertTo-Json -Depth 100 | ConvertFrom-Json

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Uri -like '*releases-index.json' } `
         -MockWith { $releasesIndex }.GetNewClosure()
}

function GivenReleasesWithLatest
{
    param (
        # List of releases
        $Release,
        # Should be parallel with Release
        $LatestSdk
    )
    $releaseWithLatest =  @()

    for ($i = 0; $i -lt $Release.Length; $i++)
    {
        $releaseWithLatest += ,@{
            'release' = $Release[$i]
            'latest-release' = $LatestSdk[$i]
        }
    }

    $releasesIndex = @{
        'releases-index' = $releaseWithLatest | ForEach-Object {
            @{
                'channel-version' = $_.'release'
                'releases.json'   = ('https://dotnetcli.pester.test.example.com/{0}/releases.json' -f $_.'release')
                'latest-sdk'  = $_.'latest-release'
            }
        }
    } | ConvertTo-Json -Depth 100 | ConvertFrom-Json

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Uri -like '*releases-index.json' } `
         -MockWith { $releasesIndex }.GetNewClosure()
}

function GivenSDKVersions
{
    param(
        $Version,
        $ForRelease
    )

    $sdkReleases = @{
        'releases' = $Version | ForEach-Object {
            @{
                'sdk' = @{
                    'version' = $_
                }
            }
        }
    } | ConvertTo-Json -Depth 100 | ConvertFrom-Json

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '*/$ForRelease/releases.json'")) `
         -MockWith { $sdkReleases }.GetNewClosure()
}

function ThenError
{
    param(
        $Message
    )

    $Global:Error | Should -Match $Message -Because 'it should write the expected error message'
}

function ThenResolvedLatestLTSVersion
{
    Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' | Where-Object { $_ -match '(\d+\.\d+\.\d+)'} | Out-Null
    $ltsVersion = $Matches[1]

    $resolvedVersion | Should -HaveCount 1 -Because 'it should only return one version'
    $resolvedVersion | Should -Be $ltsVersion -Because 'it should resolve the latest LTS version'
}

function ThenResolvedVersion
{
    param(
        [Version]$Version
    )

    $resolvedVersion | Should -HaveCount 1 -Because 'it should only return one version'
    $resolvedVersion | Should -Be $Version -Because ('it should resolve SDK version to {0}' -f $Version)
}

function ThenReturnedNothing
{
    $resolvedVersion | Should -BeNullOrEmpty -Because 'it should not return anything'
}

function WhenResolvingSdkVersion
{
    [CmdletBinding()]
    param(
        [switch]$LatestLTS,
        [String]$Version,
        $RollForward
    )

    $script:resolvedVersion = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyDotNetSdkVersion' `
                                                           -Parameter $PSBoundParameters
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when version is not a valid .NET Core release' {
    It 'should write an error' {
        Init
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        WhenResolvingSdkVersion '2.3.100' -ErrorAction SilentlyContinue
        ThenError '\.NET Core release matching "2\.3" could not be found'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version that does not exist' {
    It 'should write an error' {
        Init
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        GivenSDKVersions '2.1.100', '2.1.200', '2.1.201' -ForRelease '2.1'
        WhenResolvingSdkVersion '2.1.101' -ErrorAction SilentlyContinue
        ThenError 'could\ not\ be\ found'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when resolving SDK version' {
    It 'should resolve SDK version' {
        Init
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        GivenSDKVersions '2.1.100', '2.1.200', '2.1.201' -ForRelease '2.1'
        GivenSDKVersions '3.0.100' -ForRelease '3.0'
        WhenResolvingSdkVersion '2.1.200'
        ThenResolvedVersion '2.1.200'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when resolving a real SDK version (No mocking of web request)' {
    It 'should resolve SDK version' {
        Init
        WhenResolvingSdkVersion '2.1.801'
        ThenResolvedVersion '2.1.801'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given patch wildcard' {
    It 'should resolve SDK version' {
        Init
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        GivenSDKVersions '2.0.000' -ForRelease '2.0'
        GivenSDKVersions '2.1.100', '2.1.200', '2.1.201' -ForRelease '2.1'
        WhenResolvingSdkVersion '2.0.*'
        ThenResolvedVersion '2.0.000'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given minor wildcard' {
    It 'should resolve SDK version' {
        Init
        GivenReleases '1.0', '2.0', '2.2', '2.11', '3.0'
        GivenSDKVersions '2.0.000' -ForRelease '2.0'
        GivenSDKVersions '2.2.100', '2.2.200', '2.2.201' -ForRelease '2.2'
        GivenSDKVersions '2.11.000' -ForRelease '2.11'
        WhenResolvingSdkVersion '2.*'
        ThenResolvedVersion '2.11.000'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given major wildcard' {
    It 'should resolve SDK version' {
        Init
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        GivenSDKVersions '2.0.000' -ForRelease '2.0'
        GivenSDKVersions '2.1.000' -ForRelease '2.1'
        GivenSDKVersions '3.0.000', '3.0.100' -ForRelease '3.0'
        WhenResolvingSdkVersion '*'
        ThenResolvedVersion '3.0.100'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when resolving latest LTS version' {
    It 'should resolve SDK LTS version' {
        Init
        WhenResolvingSdkVersion -LatestLTS
        ThenResolvedLatestLTSVersion
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when latest version API doesn''t return a valid version' {
    It 'should write an error' {
        Init
        Mock -CommandName Invoke-RestMethod -ModuleName 'Whiskey' -MockWith { '1' }
        WhenResolvingSdkVersion -LatestLTS -ErrorAction SilentlyContinue
        ThenError 'Could\ not\ retrieve\ the\ latest\ LTS\ version'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when Microsoft changes the index again' {
    It 'should fail' {
        Init
        Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey'
        WhenResolvingSdkVersion -Version '2.1' -ErrorAction SilentlyContinue
        ThenError 'releases index'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when Microsoft moves the index again' {
    It 'should fail' {
        Init
        Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -MockWith { Write-Error 'I do not exist!' -ErrorAction $ErrorActionPreference }
        WhenResolvingSdkVersion -Version '2.1' -ErrorAction SilentlyContinue
        ThenError 'releases index'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when RollForward is disabled and patch is found' {
    It 'should use specified version' {
        Init
        GivenReleases '3.0'
        GivenSDKVersions '3.0.000', '3.0.100' -ForRelease '3.0'
        WhenResolvingSdkVersion -Version '3.0.000' -RollForward Disable
        ThenResolvedVersion '3.0.000'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when RollForward is disabled and patch is not found' {
    It 'should fail' {
        Init
        GivenReleases '3.0'
        GivenSDKVersions '3.0.100' -ForRelease '3.0'
        WhenResolvingSdkVersion -Version '3.0.000' -RollForward Disable
        ThenError -Message 'not be found'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when RollForward is LatestFeature and feature found' {
    It 'should find latest feature' {
        Init
        GivenReleases '3.0'
        GivenSDKVersions '3.0.010', '3.0.100', '3.0.189', '3.0.199' -ForRelease '3.0'
        WhenResolvingSdkVersion '3.0.010' -RollForward LatestFeature
        ThenResolvedVersion '3.0.199'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when RollForward is LatestMinor and minor found' {
    It 'should use latest minor' {
        Init
        GivenReleasesWithLatest -Release '3.0', '3.1' -LatestSdk '3.0.199', '3.1.400'
        GivenSDKVersions '3.0.010', '3.0.100', '3.0.189', '3.0.199' -ForRelease '3.0'
        GivenSDKVersions '3.1.100', '3.1.199', '3.1.400' -ForRelease '3.1'
        WhenResolvingSdkVersion '3.0.010' -RollForward LatestMinor
        ThenResolvedVersion '3.1.400'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVerison.when RollForward is LatestMajor and major found' {
    It 'should use latest major' {
        Init
        GivenReleasesWithLatest -Release '3.0', '3.1', '4.0' -LatestSdk '3.0.199', '3.1.400', '4.0.499'
        GivenSDKVersions '3.0.010', '3.0.100', '3.0.189', '3.0.199' -ForRelease '3.0'
        GivenSDKVersions '3.1.100', '3.1.199', '3.1.400' -ForRelease '3.1'
        GivenSDKVersions '4.0.100', '4.0.499', '4.0.498', '4.0.000' -ForRelease '4.0'
        WhenResolvingSdkVersion '3.0.010' -RollForward LatestMajor
        ThenResolvedVersion '4.0.499'
    }
}

foreach($strategy in @('patch', 'feature', 'minor', 'major', 'latestpatch'))
{
    Describe "Resolve-WhiskeyDotNetSdkVersion.when RollForward is $($strategy) and exact version does exist" {
        It 'should resolve latest patch' {
            Init
            GivenReleases '3.0'
            GivenSDKVersions '3.0.000', '3.0.001', '3.0.100' -ForRelease '3.0'
            WhenResolvingSdkVersion -Version '3.0.000' -RollForward $strategy
            ThenResolvedVersion '3.0.001'
        }
    }

    Describe "Resolve-WhiskeyDotNetSdkVersion.when RollForward is $($strategy) and exact version does not exist" {
        It 'should resolve latest patch' {
            Init
            GivenReleases '3.0'
            GivenSDKVersions '3.0.001', '3.0.002' -ForRelease '3.0'
            WhenResolvingSdkVersion '3.0.000' -RollForward $strategy
            ThenResolvedVersion '3.0.002'
        }
    }
}
