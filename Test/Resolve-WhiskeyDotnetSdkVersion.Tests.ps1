
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotNetSdkVersion.ps1')

$givenVersion = $null
$resolvedVersion = $null

function Init
{
    $Global:Error.Clear()
    $script:givenVersion = $null
    $script:resolvedVersion = $null
}

function GivenVersion
{
    param(
        $Version
    )

    $script:givenVersion = $Version
}

function ThenError
{
    param(
        $Message
    )

    It 'should write an error message' {
        $Global:Error | Should -Match $Message
    }
}

function ThenResolvedLatestLTSVersion
{
    Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' | Where-Object { $_ -match '(\d+\.\d+\.\d+)'} | Out-Null
    $ltsVersion = $Matches[1]

    It ('should resolve latest LTS version ''{0}''' -f $ltsVersion) {
        $resolvedVersion | Should -Be $ltsVersion
    }
}

function ThenResolvedVersion
{
    param(
        $Version
    )

    It ('should resolve SDK version ''{0}''' -f $Version) {
        $resolvedVersion | Should -Be $Version
    }
}

function ThenResolvedWildcardVersion
{
    param(
        $WildcardVersion
    )

    $releasesJson = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/dotnet/core/master/release-notes/releases.json'
    $sdkVersions =  $releasesJson |
                        Select-Object -ExpandProperty 'version-sdk' -Unique |
                        Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
                        Sort-Object -Descending

    $expectedVersion = $sdkVersions | Where-Object { [version]$_ -like $WildcardVersion } | Select-Object -First 1

    It ('should resolve SDK version ''{0}''' -f $expectedVersion) {
        $resolvedVersion | Should -Be $expectedVersion
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $resolvedVersion | Should -BeNullOrEmpty
    }
}

function WhenResolvingSdkVersion
{
    [CmdletBinding()]
    param()

    $versionParam = @{}
    if ($givenVersion)
    {
        $versionParam['Version'] = $givenVersion
    }

    $script:resolvedVersion = Resolve-WhiskeyDotNetSdkVersion @versionParam
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version that does not exist' {
    Init
    GivenVersion '0.0.1'
    WhenResolvingSdkVersion -ErrorAction SilentlyContinue
    ThenError 'could\ not\ be\ found'
    ThenReturnedNothing
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''2.1.2''' {
    Init
    GivenVersion '2.1.2'
    WhenResolvingSdkVersion
    ThenResolvedVersion '2.1.2'
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''2.*''' {
    Init
    GivenVersion '2.*'
    WhenResolvingSdkVersion
    ThenResolvedWildcardVersion '2.*'
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''1.0.*''' {
    Init
    GivenVersion '1.0.*'
    WhenResolvingSdkVersion
    ThenResolvedWildcardVersion '1.0.*'
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when resolving latest LTS version' {
    Init
    WhenResolvingSdkVersion
    ThenResolvedLatestLTSVersion
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when latest version API doesn''t return a valid version' {
    Init
    Mock -CommandName Invoke-RestMethod -MockWith { '1' }
    WhenResolvingSdkVersion -ErrorAction SilentlyContinue
    ThenError 'Could\ not\ retrieve\ the\ latest\ LTS\ version'
    ThenReturnedNothing
}
