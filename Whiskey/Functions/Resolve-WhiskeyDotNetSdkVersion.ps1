
function Resolve-WhiskeyDotNetSdkVersion
{
    <#
    .SYNOPSIS
    Searches for a version of the .NET Core SDK to ensure it exists and returns the resolved version.

    .DESCRIPTION
    The `Resolve-WhiskeyDotNetSdkVersion` function ensures a given version is a valid released version of the .NET Core SDK. By default, the function will return the latest LTS version of the SDK. If a `Version` number is given then that version is compared against the list of released SDK versions to ensure the given version is valid. If no valid version is found matching `Version`, then an error is written and nothing is returned.

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
        [Whiskey.DotNetSdkRollForward] $RollForward = [Whiskey.DotNetSdkRollForward]::Disable
    )

    function Get-AvailableSdkVersions
    {
        param (
            $ReleasesIndex,
            $TargetMajor,
            $TargetMinor
        )
        $releaseUri =
            $ReleasesIndex |
            Where-Object { $_.'channel-version' -like "$($TargetMajor).$($TargetMinor)" } |
            Select-Object -First 1 |
            Select-Object -ExpandProperty 'releases.json'
        if ( -not $releaseUri )
        {
            return
        }

        $releasesJson = Invoke-RestMethod -Uri $releaseUri -ErrorAction Stop

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

        $sortedSdkVersions =
            $sdkVersions |
                ForEach-Object {
                    $_ -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' | Out-Null
                    [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
                } |
                Sort-Object -Descending
        return $sortedSdkVersions
    }

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

    $Version -match '^\d+\.(?:\d+|\*)|^\*' | Out-Null
    $matcher = $Matches[0]

    $release = $releasesIndex | Where-Object { $_.'channel-version' -like $matcher } | Select-Object -First 1
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
    if ( $Version -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' )
    {
        $desiredVersion = [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
        $sortedSdkVersions =
            $sdkVersions |
            ForEach-Object {
                $_ -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' | Out-Null
                [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
            } |
            Where-Object { $_ -ge $desiredVersion } |
            Sort-Object -Descending
    }

    $installedVersions = Get-InstalledDotNetSdk
    if ( $installedVersions )
    {
        $installedVersions = $installedVersions |
            ForEach-Object {
                $_ -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' | Out-Null
                [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
            }
    }

    Write-Verbose "Installed Versions: $($installedVersions)" -Verbose
    Write-Verbose "Sorted versions: $($sortedSdkVersions)" -Verbose

    $resolvedVersion = $null
    switch ($RollForward)
    {
        Disable
        {
            $resolvedVersion =
                $sdkVersions |
                Where-Object { $_ -like $Version } |
                Sort-Object -Descending |
                Select-Object -First 1
        }
        Patch
        {
            $sortedSdkVersions =
                $sortedSdkVersions |
                Where-Object { $_.Build -eq $desiredVersion.Build }
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions } |
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        Feature
        {
            $expectedBuild = $sortedSdkVersions | Select-Object -Last 1
            if ( $expectedBuild )
            {
                $sortedSdkVersions =
                    $sortedSdkVersions |
                    Where-Object {
                        $_.Build -eq $expectedBuild.Build
                    }
            }
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions } |
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        Minor
        {
            if ( -not $sortedSdkVersions )
            {
                $sortedSdkVersions = Get-AvailableSdkVersions -ReleasesIndex $releasesIndex `
                                                              -TargetMajor $desiredVersion.Major `
                                                              -TargetMinor ($desiredVersion.Minor + 1)
                $expectedBuild = [Version] "0.0.1"
            }
            else
            {
                $expectedBuild = $sortedSdkVersions | Select-Object -Last 1
            }

            if ( $expectedBuild )
            {
                $sortedSdkVersions =
                    $sortedSdkVersions |
                    Where-Object { $_.Build -eq $expectedBuild.Build }
            }
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions } |
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        Major
        {
            if ( -not $sortedSdkVersions )
            {
                $sortedSdkVersions = Get-AvailableSdkVersions -ReleasesIndex $releasesIndex `
                                                              -TargetMajor ($desiredVersion.Major + 1)`
                                                              -TargetMinor 0
                $expectedBuild = [Version] "0.0.1"
            }
            else
            {
                $expectedBuild = $sortedSdkVersions | Select-Object -Last 1
            }
            if ( $expectedBuild )
            {
                $sortedSdkVersions =
                    $sortedSdkVersions |
                    Where-Object { $_.Build -eq $expectedBuild.Build }
            }
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions } |
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        LatestPatch
        {
            $sortedSdkVersions =
                $sortedSdkVersions |
                Where-Object { $_.Build -eq $desiredVersion.Build }
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions }
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        LatestFeature
        {
            $sortedSdkVersions =
                $sortedSdkVersions
            $resolvedVersion =
                $sortedSdkVersions |
                Where-Object { $_ -in $installedVersions }
                Select-Object -First 1
            if ( -not $resolvedVersion )
            {
                $resolvedVersion = $sortedSdkVersions | Select-Object -First 1
            }
        }
        LatestMinor
        {
            $latestMinorVersion =
                $releasesIndex |
                Where-Object { [Version]::TryParse($_.'channel-version', [ref]$null) } |
                ForEach-Object {
                    $channelVersion = $_ | Select-Object -ExpandProperty 'channel-version'
                    $channelVersion -as [Version]
                } |
                Where-Object {
                    $_.Major -eq $desiredVersion.Major -and
                    $_.Minor -ge $desiredVersion.Minor
                } |
                Sort-Object -Descending |
                Select-Object -First 1
            $resolvedVersion = $releasesIndex |
                Where-Object { $_.'channel-version' -like "$($latestMinorVersion.Major).$($latestMinorVersion.Minor)"} |
                Select-Object -ExpandProperty 'latest-sdk'
        }
        LatestMajor
        {
            $latestMinorVersion =
                $releasesIndex |
                Where-Object { [Version]::TryParse($_.'channel-version', [ref]$null) } |
                ForEach-Object {
                    $channelVersion = $_ | Select-Object -ExpandProperty 'channel-version'
                    $channelVersion -as [Version]
                } |
                Where-Object {
                    $_.Major -ge $desiredVersion.Major -and
                    $_.Minor -ge $desiredVersion.Minor
                } |
                Sort-Object -Descending |
                Select-Object -First 1
            $resolvedVersion = $releasesIndex |
                Where-Object { $_.'channel-version' -like "$($latestMinorVersion.Major).$($latestMinorVersion.Minor)"} |
                Select-Object -ExpandProperty 'latest-sdk' |
                Select-Object -First 1
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