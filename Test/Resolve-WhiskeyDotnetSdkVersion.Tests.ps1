
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotNetSdkVersion.ps1')

$resolvedVersion = $null

function Init
{
    $Global:Error.Clear()
    $script:resolvedVersion = $null
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

    $resolvedVersion | Should -Be $ltsVersion -Because 'it should resolve the latest LTS version'
}

function ThenResolvedVersion
{
    param(
        $Version
    )

    $resolvedVersion | Should -Be $Version -Because ('it should resolve SDK version to "{0}"' -f $Version)
}

function ThenResolvedWildcardVersion
{
    param(
        $WildcardVersion
    )

    $releasesJson = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/dotnet/core/master/release-notes/releases.json'
    $sdkVersions =
        $releasesJson |
        Select-Object -ExpandProperty 'version-sdk' -Unique |
        Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
        Sort-Object -Descending

    $expectedVersion = $sdkVersions | Where-Object { [version]$_ -like $WildcardVersion } | Select-Object -First 1

    $resolvedVersion | Should -Be $expectedVersion -Because ('it should resolve SDK version to "{0}"' -f $expectedVersion)
}

function ThenReturnedNothing
{
    $resolvedVersion | Should -BeNullOrEmpty -Because 'it should not return anything'
}

function WhenResolvingSdkVersion
{
    [CmdletBinding()]
    param(
        $Version
    )

    $versionParam = @{}
    if ($Version)
    {
        $versionParam['Version'] = $Version
    }

    $script:resolvedVersion = Resolve-WhiskeyDotNetSdkVersion @versionParam
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version that does not exist' {
    It 'should write an error' {
        Init
        WhenResolvingSdkVersion '0.0.1' -ErrorAction SilentlyContinue
        ThenError 'could\ not\ be\ found'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version "2.1.2"' {
    It 'should resolve SDK version' {
        Init
        WhenResolvingSdkVersion '2.1.2'
        ThenResolvedVersion '2.1.2'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version "2.*"' {
    It 'should resolve SDK version' {
        Init
        WhenResolvingSdkVersion '2.*'
        ThenResolvedWildcardVersion '2.*'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version "1.0.*"' {
    It 'should resolve SDK version' {
        Init
        WhenResolvingSdkVersion '1.0.*'
        ThenResolvedWildcardVersion '1.0.*'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when resolving latest LTS version' {
    It 'should resolve SDK LTS version' {
        Init
        WhenResolvingSdkVersion
        ThenResolvedLatestLTSVersion
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when latest version API doesn''t return a valid version' {
    It 'should write an error' {
        Init
        Mock -CommandName Invoke-RestMethod -MockWith { '1' }
        WhenResolvingSdkVersion -ErrorAction SilentlyContinue
        ThenError 'Could\ not\ retrieve\ the\ latest\ LTS\ version'
        ThenReturnedNothing
    }
}
