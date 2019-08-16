
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotNetSdkVersion.ps1')

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
        $Version
    )

    $resolvedVersion | Should -HaveCount 1 -Because 'it should only return one version'
    $resolvedVersion | Should -Be $Version -Because ('it should resolve SDK version to "{0}"' -f $Version)
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
        [string]$Version
    )

    $param = @{}
    if ($Version)
    {
        $param['Version'] = $Version
    }

    if ($LatestLTS)
    {
        $param['LatestLTS'] = $true
    }

    $script:resolvedVersion = Resolve-WhiskeyDotNetSdkVersion @param
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
        GivenReleases '1.0', '2.0', '2.1', '3.0'
        GivenSDKVersions '2.0.000' -ForRelease '2.0'
        GivenSDKVersions '2.1.100', '2.1.200', '2.1.201' -ForRelease '2.1'
        WhenResolvingSdkVersion '2.*'
        ThenResolvedVersion '2.1.201'
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
        Mock -CommandName Invoke-RestMethod -MockWith { '1' }
        WhenResolvingSdkVersion -LatestLTS -ErrorAction SilentlyContinue
        ThenError 'Could\ not\ retrieve\ the\ latest\ LTS\ version'
        ThenReturnedNothing
    }
}
