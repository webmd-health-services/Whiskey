
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
    #>
    [CmdletBinding(DefaultParameterSetName='LatestLTS')]
    param(
        [Parameter(ParameterSetName='LatestLTS')]
        # Returns the latest LTS version of the .NET Core SDK.
        [switch]$LatestLTS,

        [Parameter(Mandatory, ParameterSetName='Version')]
        # Version of the .NET Core SDK to search for and resolve. Accepts wildcards.
        [String]$Version,

        # Roll forward preferences for the .NET Core SDK
        [Whiskey.DotNetSdkRollForward]$RollForward = [Whiskey.DotNetSdkRollForward]::Disable
    )

    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    function ConvertTo-VersionObject
    {
        param(
            # A version in the form 3.0.300
            [Parameter(Mandatory)]
            [String] $VersionToConvert
        )

        $versionObject = $null
        if ($VersionToConvert -match '(?<major>\d+)\.(?<minor>\d+)\.(?<feature>\d)(?<patch>\d\d)')
        {
            $versionObject = [pscustomobject]@{
                Patch = [int]$Matches.patch
                Feature = [int]$Matches.feature
                Minor = [int]$Matches.minor
                Major = [int]$Matches.Major
                Text = $VersionToConvert
            }
        }
        return $versionObject
    }

    function Get-MaxPatch
    {
        param(
            # A feature value
            [Parameter(Mandatory)]
            [int] $Feature,
            # A list of possible SDK versions
            [Parameter(Mandatory)]
            [array] $SdkVersionObjs,
            # A specific minimum patch
            [int] $MinimumPatch
        )

        if (-not $MinimumPatch)
        {
            $SdkVersionObjs = $SdkVersionObjs | Where-Object { $_.Feature -eq $Feature }
        }
        else
        {
            $SdkVersionObjs = $SdkVersionObjs | 
                Where-Object { $_.Feature -eq $Feature -and $_.Patch > $MinimumPatch}
        }
        if ( ($SdkVersionObjs | Measure-Object | Select-Object -ExpandProperty 'Count') -lt 1)
        {
            return
        }
        $maxPatch = [String]($SdkVersionObjs | 
            ForEach-Object { $_.patch } | 
            Measure-Object -Maximum | 
            Select-Object -ExpandProperty 'Maximum')
        if ($maxPatch.Length -eq 1) 
        {
            $maxPatch = "0$($maxPatch)"
        }
        return $maxPatch
    }

    function Get-NextFeature
    {
        param(
            # Version to search for
            [Parameter(Mandatory)]
            [int] $SearchFeature,
            [Parameter(Mandatory)]
            # The list of possible SDK versions
            [array] $SdkVersionObjs,
            # The minimum required patch for the feature
            [int] $MinimumPatch
        )
        $maxPatch = Get-MaxPatch -Feature $SearchFeature -SdkVersionObjs $SdkVersionObjs -MinimumPatch $MinimumPatch

        if ( -not $maxPatch )
        {
            $nextFeature = $SdkVersionObjs |
                ForEach-Object { $_.Feature } |
                Where-Object { $_ -gt $SearchFeature } |
                Sort-Object |
                Select-Object -First 1
            
            if ( -not $nextFeature )
            {
                return
            }
            $maxPatch = Get-MaxPatch -Feature $nextFeature -SdkVersionObjs $SdkVersionObjs
            return @{
                Patch = $maxPatch
                Feature = $nextFeature
            }
        }
        return [pscustomobject]@{
            Patch = $maxPatch
            Feature = $SearchFeature
        }
    }

    function Get-NextMinor
    {
        param(
            # Version to search for
            [Parameter(Mandatory)]
            [object]$SearchVersionObj,
            # List of versions to initially check
            [Parameter(Mandatory)]
            [array]$SdkVersionObjs,
            # A list of all valid releases
            [Parameter(Mandatory)]
            [array]$ReleasesIndex
        )
        $featurePatch = Get-NextFeature -SearchFeature $SearchVersionObj.Feature -SdkVersionObjs $SdkVersionObjs
        if ( -not $featurePatch -or ($featurePatch.Patch -lt $SearchVersionObj.Patch) )
        {
            $nextMinor = "$($SearchVersionObj.Major).$($searchVersionObj.Minor + 1)"
            $sdkVersions = Get-NewReleases -Version $nextMinor -ReleasesIndex $ReleasesIndex
            if ( -not $sdkVersions )
            {
                return
            }
            $sdkVersionObjs = $sdkVersions |
                ForEach-Object { ConvertTo-VersionObject -VersionToConvert $_ }
            $featurePatch = Get-NextFeature -SearchFeature 0 -SdkVersionObjs $sdkVersionObjs
            if ( -not $featurePatch )
            {
                return
            }
            return [pscustomobject]@{
                Major = $SearchVersionObj.Major
                Minor = $SearchVersionObj.Minor + 1
                Feature = $featurePatch.Feature
                Patch = $featurePatch.Patch
            }
        }
        else
        {
            return [pscustomobject]@{
                Major = $SearchVersionObj.Major
                Minor = $SearchVersionObj.Minor
                Feature = $featurePatch.Feature
                Patch = $featurePatch.Patch
            }
        }
    }

    function Get-NewReleases
    {
        param(
            # The major and minor version to search for
            [Parameter(Mandatory)]
            [String]$Version,
            # The current releases index
            [Parameter(Mandatory)]
            [array]$ReleasesIndex
        )

        $release = $ReleasesIndex | 
            Where-Object { $_.'channel-version' -like $Version } | 
            Select-Object -First 1
        if ( -not $release )
        {
            return
        }
        $releasesJsonUri = $release | Select-Object -ExpandProperty 'releases.json'
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
        return $sdkVersions
    }

    if ($Version)
    {
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
        if (-not $release)
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

        if ( $RollForward )
        {
            $sdkVersionObjs = $sdkVersions | ForEach-Object { ConvertTo-VersionObject -VersionToConvert $_ }
            $searchVersionObj = ConvertTo-VersionObject -VersionToConvert $Version
        }
        $resolvedVersion = $null

        switch ($RollForward)
        {
            Patch 
            {
                $resolvedVersion = 
                    $sdkVersionObjs | 
                    Where-Object { $_.Text -eq $searchVersionObj.Text } | 
                    Select-Object -First 1 | 
                    Select-Object -ExpandProperty 'Text'
                if ( -not $resolvedVersion )
                {
                    $maxPatch = Get-MaxPatch -Feature $searchVersionObj.Feature `
                                             -SdkVersionObjs $sdkVersionObjs `
                                             -MinimumPatch $searchVersionObj.Patch
                    if ( -not $maxPatch )
                    {
                        $msg = "A released version of the .NET Core SDK matching feature $($searchVersionObj.Feature)" +
                        " and patch >= $($searchVersionObj.Patch) could not be found."
                        Write-WhiskeyError -Message $msg
                        return
                    }
                    $resolvedVersion = "$($searchVersionObj.Major).$($searchVersionObj.Minor)."+
                                       "$($searchVersionObj.Feature)$($maxPatch)"
                }
            }
            Feature
            {
                $featurePatch = Get-NextFeature -SearchFeature $searchVersionObj.Feature -SdkVersionObjs $sdkVersionObjs
                if ( -not $featurePatch )
                {
                    $msg = "A released version of the .NET Core SDK matching minor version $($searchVersionObj.Minor)" +
                           " and feature >= $($searchVersionObj.Feature) could not be found"
                    Write-WhiskeyError -Message $msg
                    return
                }
                $resolvedVersion = "$($searchVersionObj.Major).$($searchVersionObj.Minor).$($featurePatch.Feature)" +
                                   "$($featurePatch.Patch)"
            }
            Minor
            {
                $minorVersion = Get-NextMinor -SearchVersionObj $searchVersionObj `
                                          -SdkVersionObjs $sdkVersionObjs `
                                          -ReleasesIndex $releasesIndex
                if ( -not $minorVersion )
                {
                    $msg = "A released version of the .NET Core SDK matching major version " +
                            "$($SearchVersionObj.Major) or matching minor version $($searchVersionObj.Minor)" +
                            " or $($SearchVersionObj.Minor + 1) could not be found."
                    Write-WhiskeyError -Message $msg
                    return
                }
                $resolvedVersion = "$($minorVersion.Major).$($minorVersion.Minor).$($minorVersion.Feature)" +
                                   "$($minorVersion.Patch)"
            }
            Major
            {
                $minorVersion = Get-NextMinor -SearchVersionObj $searchVersionObj `
                                          -SdkVersionObjs $sdkVersionObjs `
                                          -ReleasesIndex $releasesIndex
                if ( -not $minorVersion )
                {
                    $nextMajorMinor = "$($searchVersionObj.Major + 1).0"
                    $sdkVersions = Get-NewReleases -Version $nextMajorMinor -ReleasesIndex $releasesIndex
                    $sdkVersionObjs = 
                        $sdkVersions | 
                        ForEach-Object { ConvertTo-VersionObject -VersionToConvert $_ }
                    $newSearchObj = ConvertTo-VersionObject -VersionToConvert "$($nextMajorMinor).000"
                    if ( -not $sdkVersionObjs )
                    {
                        $msg = "A released version of the .NET Core SDK matching major version " +
                               "$($searchVersionObj.Major) with a minor version greater or equal to " + 
                               "$($searchVersionObj.Minor) could not be found"
                        Write-WhiskeyError -Message $msg
                        return
                    }
                    $minorVersion = Get-NextMinor -SearchVersionObj $newSearchObj -SdkVersionObjs $sdkVersionObjs -ReleasesIndex $releasesIndex
                    if ( -not $minorVersion )
                    {
                        $msg = "A released version of the .NET Core SDK matching major version " +
                               "$($searchVersionObj.Major) with a minor version greater or equal to " + 
                               "$($searchVersionObj.Minor) could not be found"
                        Write-WhiskeyError -Message $msg
                        return
                    }
                }
                $resolvedVersion = "$($minorVersion.Major).$($minorVersion.Minor).$($minorVersion.Feature)" +
                                   "$($minorVersion.Patch)"
            }
            LatestPatch
            {
                $maxPatch = Get-MaxPatch -Feature $searchVersionObj.Feature -SdkVersionObjs $sdkVersionObjs
                if ( $maxPatch )
                {
                    $resolvedVersion = "$($searchVersionObj.Major).$($searchVersionObj.Minor)." + 
                                       "$($searchVersionObj.Feature)$($maxPatch)"
                }
            }
            LatestFeature
            {
                $maxFeature = 
                    $sdkVersionObjs |
                    ForEach-Object { $_.Feature } |
                    Measure-Object -Maximum |
                    Select-Object -ExpandProperty 'Maximum'
                if ( $maxFeature )
                {
                    $maxPatch = Get-MaxPatch -Feature $maxFeature -SdkVersionObjs $sdkVersionObjs
                    if ( $maxPatch )
                    {
                        $resolvedVersion = "$($searchVersionObj.Major).$($searchVersionObj.Minor)." + 
                                        "$($maxFeature)$($maxPatch)"
                    }
                }
            }
            LatestMinor
            {
                $maxMinor = 
                    $releasesIndex |
                    ForEach-Object { 
                        $_.'channel-version' -Match '(?<major>\d+)\.(?<minor>\d+)' | Out-Null
                        return [pscustomobject] @{
                            Major=$Matches.major
                            Minor=$Matches.minor
                        }
                    } |
                    Where-Object { $_.Major -eq $searchVersionObj.Major } | 
                    ForEach-Object { $_.Minor } |
                    Measure-Object -Maximum |
                    Select-Object -ExpandProperty 'Maximum'
                if ( $maxMinor )
                {
                    $sdkVersions = Get-NewReleases -Version "$($searchVersionObj.Major).$($maxMinor)" -ReleasesIndex $releasesIndex
                    $sdkVersionObjs = $sdkVersions | ForEach-Object { ConvertTo-VersionObject -VersionToConvert $_ }

                    $maxFeature = 
                        $sdkVersionObjs |
                        ForEach-Object { $_.Feature } |
                        Measure-Object -Maximum |
                        Select-Object -ExpandProperty 'Maximum'
                    if ( $maxFeature )
                    {
                        $maxPatch = Get-MaxPatch -Feature $maxFeature -SdkVersionObjs $sdkVersionObjs
                        if ( $maxPatch )
                        {
                            $resolvedVersion = "$($searchVersionObj.Major).$($maxMinor)." + 
                                            "$($maxFeature)$($maxPatch)"
                        }
                    }
                }
            }
            LatestMajor
            {
                $majorMinorOptions = 
                    $releasesIndex |
                    ForEach-Object {
                        $_.'channel-version' -Match '(?<major>\d+)\.(?<minor>\d+)' | Out-Null
                        return [pscustomobject] @{
                            Major=[int]$Matches.major
                            Minor=[int]$Matches.minor
                        }
                    }
                $maxMajor = 
                    $majorMinorOptions |
                    ForEach-Object { $_.Major } |
                    Get-Unique |
                    Measure-Object -Maximum |
                    Select-Object -ExpandProperty 'Maximum'
                if ( $null -ne $maxMajor )
                {
                    $maxMinor = 
                        $majorMinorOptions |
                        Where-Object { $_.Major -eq $maxMajor } |
                        ForEach-Object { $_.Minor } |
                        Measure-Object -Maximum |
                        Select-Object -ExpandProperty 'Maximum'
                    if ($null -ne $maxMinor)
                    {
                        $sdkVersions = Get-NewReleases -Version "$($maxMajor).$($maxMinor)" -ReleasesIndex $releasesIndex
                        $sdkVersionObjs = $sdkVersions | ForEach-Object { ConvertTo-VersionObject -VersionToConvert $_ }
                        $maxFeature = 
                            $sdkVersionObjs |
                            ForEach-Object { $_.Feature } |
                            Measure-Object -Maximum |
                            Select-Object -ExpandProperty 'Maximum'
                        if ( $maxFeature )
                        {
                            $maxPatch = Get-MaxPatch -Feature $maxFeature -SdkVersionObjs $sdkVersionObjs
                            if ( $maxPatch )
                            {
                                $resolvedVersion = "$($maxMajor).$($maxMinor)." + 
                                                "$($maxFeature)$($maxPatch)"
                            }
                        }
                    }
                }
            }
            Disable 
            {
                $resolvedVersion =
                    $sdkVersions |
                    Where-Object { $_ -like $Version } |
                    Sort-Object -Descending |
                    Select-Object -First 1
            }
        }



        if (-not $resolvedVersion)
        {
            Write-WhiskeyError -Message ('A released version of the .NET Core SDK matching "{0}" could not be found in "{1}" with rollForward value in global.json set to {2}' -f $Version, $releasesJsonUri, $RollForward)
            return
        }

        Write-WhiskeyVerbose -Message ('[{0}] SDK version "{1}" resolved to "{2}"' -f $MyInvocation.MyCommand,$Version,$resolvedVersion)
    }
    else
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
    }

    return $resolvedVersion
}
