
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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

    $Global:Error | Should -Match $Message
}

function ThenResolvedLatestLTSVersion
{
    Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' | Where-Object { $_ -match '(\d+\.\d+\.\d+)'} | Out-Null
    $ltsVersion = $Matches[1]

    $resolvedVersion | Should -Be $ltsVersion
}

function ThenResolvedVersion
{
    param(
        $Version
    )

    $resolvedVersion | Should -Be $Version
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

    $resolvedVersion | Should -Be $expectedVersion
}

function ThenReturnedNothing
{
    $resolvedVersion | Should -BeNullOrEmpty
}

function WhenResolvingSdkVersion
{
    [CmdletBinding()]
    param()

    $parameter = @{}
    if ($givenVersion)
    {
        $parameter['Version'] = $givenVersion
    }

    if( $PSBoundParameters.ContainsKey('ErrorAction') )
    {
        $parameter['ErrorAction'] = $ErrorActionPreference
    }
    $script:resolvedVersion = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyDotNetSdkVersion' -Parameter $parameter
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version that does not exist' {
    It 'should fail' {
        Init
        GivenVersion '0.0.1'
        WhenResolvingSdkVersion -ErrorAction SilentlyContinue
        ThenError 'could\ not\ be\ found'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''2.1.2''' {
    It 'should resolve to 2.1.1' {
        Init
        GivenVersion '2.1.2'
        WhenResolvingSdkVersion
        ThenResolvedVersion '2.1.2'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''2.*''' {
    It 'should resolve to latest 2 version' {
        Init
        GivenVersion '2.*'
        WhenResolvingSdkVersion
        ThenResolvedWildcardVersion '2.*'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when given SDK version ''1.0.*''' {
    It 'should resolve to latest patch version' {
        Init
        GivenVersion '1.0.*'
        WhenResolvingSdkVersion
        ThenResolvedWildcardVersion '1.0.*'
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when no version given' {
    It 'should get the latest LTS version' {
        Init
        WhenResolvingSdkVersion
        ThenResolvedLatestLTSVersion
    }
}

Describe 'Resolve-WhiskeyDotNetSdkVersion.when latest version API doesn''t return a valid version' {
    It 'should fail' {
        Init
        Mock -CommandName Invoke-RestMethod -ModuleName 'Whiskey' -MockWith { '1' }
        WhenResolvingSdkVersion -ErrorAction SilentlyContinue
        ThenError 'Could\ not\ retrieve\ the\ latest\ LTS\ version'
        ThenReturnedNothing
    }
}
