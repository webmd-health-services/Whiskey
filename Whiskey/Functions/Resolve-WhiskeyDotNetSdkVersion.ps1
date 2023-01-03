
function Resolve-WhiskeyDotNetSdkVersion
{
    <#
    .SYNOPSIS
    Searches for a version of the .NET Core SDK to ensure it exists and returns the resolved version.

    .DESCRIPTION
    The `Resolve-WhiskeyDotNetSdkVersion` function ensures a given version is a valid released version of the .NET Core SDK. By default, the function will return the latest LTS version of the SDK. If a `Version` number is given then that version is compared against the list of released SDK versions to ensure the given version is valid. If no valid version is found matching `Version`, then an error is written and nothing is returned.
    The logic for the provided RollForward value is as follows: For `Patch`, `Feature`, `Major`, and `Minor`, the most recent patch for the specified versions is returned. For `LatestPatch`, the latest patch for the specified major, minor, and feature versions is used. For `LatestFeature`, the latest patch and feature is used for the provided major and minor versions. For `LatestMinor`, the latest minor, feature, and patch are used
    for the specified major version. For `LatestMajor`, the most recently released version of the .NET Core SDK is used.

    .EXAMPLE
    Resolve-WhiskeyDotNetSdkVersion -LatestLTS

    Demonstrates returning the latest LTS version of the .NET Core SDK.

    .EXAMPLE
    Resolve-WhiskeyDotNetSdkVersion -Version '2.1.2'

    Demonstrates ensuring that version '2.1.2' is a valid released version of the .NET Core SDK.

    .EXAMPLE
    Resolve-WhiskeyDotNetSdkVersion -Version '2.*'

    Demonstrates resolving the latest '2.x.x' version of the .NET Core SDK.

    .EXAMPLE
    Resolve-WhiskeyDotNetSdkVersion -Version '2.1.2' -RollForward Patch

    Demonstrates finding the latest '2.1.x' version of the .NET Core SDK.
    #>
    [CmdletBinding(DefaultParameterSetName='LatestLTS')]
    param(
        [Parameter(ParameterSetName='LatestLTS')]
        # Returns the latest LTS version of the .NET Core SDK.
        [switch] $LatestLTS,

        [Parameter(Mandatory, ParameterSetName='Version')]
        # Version of the .NET Core SDK to search for and resolve. Accepts wildcards.
        [String] $Version,

        # Roll forward preferences for the .NET Core SDK
        [Parameter(ParameterSetName='Version')]
        [Whiskey.DotNetSdkRollForward] $RollForward = [Whiskey.DotNetSdkRollForward]::Disable
    )
    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    if ( $LatestLTS )
    {
        $latestLTSVersionUri = 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version'

        Write-WhiskeyVerbose -Message ('[{0}] Resolving latest LTS version of .NET Core SDK from: "{1}"' -f $MyInvocation.MyCommand,$latestLTSVersionUri)
        $latestLTSVersion = Invoke-RestMethod -Uri $latestLTSVersionUri -ErrorAction Stop

        if ($latestLTSVersion -match '(\d+\.\d+\.\d+)')
        {
            $resolvedVersion = $Matches[1]
        }
        else
        {
            Write-WhiskeyError -Message ('Could not retrieve the latest LTS version of the .NET Core SDK. "{0}" returned:{1}{2}' -f $latestLTSVersionUri,[Environment]::NewLine,$latestLTSVersion)
            return
        }

        Write-WhiskeyVerbose -Message ('[{0}] Latest LTS version resolved as: "{1}"' -f $MyInvocation.MyCommand,$resolvedVersion)
        return $resolvedVersion
    }

    $urisToTry = @(
        'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json',
        'https://raw.githubusercontent.com/dotnet/core/master/release-notes/releases-index.json'
    )
    $releasesIndex = $null
    foreach( $uri in $urisToTry )
    {
        $releasesIndex =
            Invoke-RestMethod -Uri $uri -ErrorAction Ignore |
            Select-Object -ExpandProperty 'releases-index' -ErrorAction Ignore

        if( $releasesIndex )
        {
            $releasesIndexUri = $uri
            break
        }
    }

    if( -not $releasesIndex )
    {
        Write-WhiskeyError -Message ('Unable to find the .NET Core releases index. We tried each of these URIs:{0} {0}* {1}{0} ' -f [Environment]::NewLine,($urisToTry -join ('{0}* ' -f [Environment]::NewLine)))
        return
    }

    $releasesIndex =
        $releasesIndex |
        Where-Object { [Version]::TryParse($_.'channel-version', [ref]$null) } |
        ForEach-Object {
            $_.'channel-version' = [Version]$_.'channel-version'
            $_
        } |
        Sort-Object -Property 'channel-version' -Descending

    # $Version -match '^\d+\.(?:\d+|\*)|^\*' | Out-Null
    if ($Version -match '^\*|^\d+\.\*')
    {
        $matcher = $Matches[0]
    }
    elseif ($Version -match '^(\d+)\.(\d+)')
    {
        switch ($RollForward)
        {
            LatestMajor
            {
                $matcher = '*'
            }
            LatestMinor
            {
                $matcher = "$($Matches[1]).*"
            }
            default
            {
                $matcher = "$($Matches[1]).$($Matches[2])"
            }
        }
    }

    $release = $releasesIndex |
        Sort-Object -Property 'channel-version' -Descending |
        Where-Object { $_.'channel-version' -like $matcher } |
        Select-Object -First 1
    if (-not $release -and $RollForward -eq [Whiskey.DotNetSdkRollForward]::Disable)
    {
        Write-WhiskeyError -Message ('.NET Core release matching "{0}" could not be found in "{1}"' -f $matcher, $releasesIndexUri)
        return
    }

    $releasesJsonUri = $release | Select-Object -ExpandProperty 'releases.json'
    Write-WhiskeyVerbose -Message ('[{0}] Resolving .NET Core SDK version "{1}" against known released versions at: "{2}"' -f $MyInvocation.MyCommand,$Version,$releasesJsonUri)

    $releasesJson = Invoke-RestMethod -Uri $releasesJsonUri -ErrorAction Stop

    $sdkVersions = & {
        $releasesJson.releases |
            Where-Object { $_ | Get-Member -Name 'sdk' } |
            Select-Object -ExpandProperty 'sdk' |
            Select-Object -ExpandProperty 'version'

        $releasesJson.releases |
            Where-Object { $_ | Get-Member -Name 'sdks' } |
            Select-Object -ExpandProperty 'sdks' |
            Select-Object -ExpandProperty 'version'
    }

    $desiredVersion = $null
    $sortedSdkVersions = $null

    if ([WildcardPattern]::ContainsWildcardCharacters($Version))
    {
        $resolvedVersion =
            $sdkVersions |
            Where-Object { $_ -like $Version} |
            Sort-Object -Descending |
            Select-Object -First 1
        Write-WhiskeyVerbose -Message ('[{0}] SDK version "{1}" resolved to "{2}' -f $MyInvocation.MyCommand, $Version, $resolvedVersion)
        return $resolvedVersion
    }

    if ( $Version -notmatch '^(\d+)\.(\d+)\.(\d{1})(\d+)' )
    {
        $msg = ".NET SDK version ""$($Version)"" is invalid. The SDK version must be in the form of a 3-part version " +
               "number. See https://learn.microsoft.com/en-us/dotnet/core/versions/ for more information."
        Write-WhiskeyError -Message $msg
        return
    }

    $desiredVersion = [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
    $sortedSdkVersions =
        $sdkVersions |
        ForEach-Object {
            $_ -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' | Out-Null
            [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
        } |
        Sort-Object -Descending

    $resolvedVersion = $null
    switch ($RollForward)
    {
        Disable
        {
            $resolvedVersion = $sortedSdkVersions |
                Where-Object { $_ -eq $desiredVersion } |
                Select-Object -First 1
        }
        {
            $_ -eq [Whiskey.DotNetSdkRollForward]::Patch -or
            $_ -eq [Whiskey.DotNetSdkRollForward]::Feature -or
            $_ -eq [Whiskey.DotNetSdkRollForward]::Major -or
            $_ -eq [Whiskey.DotNetSdkRollForward]::Minor -or
            $_ -eq [Whiskey.DotNetSdkRollForward]::LatestPatch
        }
        {
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object {
                    $_.Major -eq $desiredVersion.Major -and
                    $_.Minor -eq $desiredVersion.Minor -and
                    $_.Build -eq $desiredVersion.Build
                } |
                Select-Object -First 1
        }
        LatestFeature
        {
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object {
                    $_.Major -eq $desiredVersion.Major -and
                    $_.Minor -eq $desiredVersion.Minor -and
                    $_.Build -ge $desiredVersion.Build
                } |
                Select-Object -First 1
        }
        {
            $_ -eq [Whiskey.DotNetSdkRollForward]::LatestMinor -or
            $_ -eq [Whiskey.DotNetSdkRollForward]::LatestMajor
        }
        {
            $resolvedVersion = $release | Select-Object -ExpandProperty 'latest-sdk'
        }
        Default
        {
            $validStrategies = [Whiskey.DotNetSdkRollForward].GetEnumNames()
            $msg = "Roll forward strategy $($RollForward) is not one of the valid .NET SDK roll forward strategies: " +
                   "$($validStrategies -join ', ')."
            Write-WhiskeyError -Message $msg
            return
        }
    }

    if ( -not $resolvedVersion)
    {
        Write-WhiskeyError -Message ('A released version of the .NET Core SDK matching "{0}" could not be found in "{1}" with rollForward value in global.json set to {2}' -f $Version, $releasesJsonUri, $RollForward)
        return
    }

    if ( $resolvedVersion -is [Version] )
    {
        $resolvedVersion = '{0}.{1}.{2}{3:00}' -f $resolvedVersion.Major, $resolvedVersion.Minor, $resolvedVersion.Build, $resolvedVersion.Revision
    }

    Write-WhiskeyVerbose -Message ('[{0}] SDK version "{1}" resolved to "{2}' -f $MyInvocation.MyCommand, $Version, $resolvedVersion)
    return $resolvedVersion
}