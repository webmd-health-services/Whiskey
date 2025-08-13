
function Install-WhiskeyNuGetPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Name,

        [String] $Version,

        [Parameter(Mandatory)]
        [String] $BuildRootPath
    )

    # We don't want `Invoke-RestMethod` to throw a terminating error so wrap it in a try/catch block.
    function Invoke-RestMethod
    {
        [CmdletBinding()]
        param(
            [Uri] $Uri
        )

        $numErrorsBefore = $Global:Error.Count
        try
        {
            Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
        }
        catch
        {
            Write-Error $_ -ErrorAction $ErrorActionPreference
        }

        if ($ErrorActionPreference -eq 'Ignore')
        {
            $numErrorsToClear = $Global:Error.Count - $numErrorsBefore
            for ($idx = 0; $idx -lt $numErrorsToClear; ++$idx)
            {
                $Global:Error.RemoveAt(0)
            }
        }
    }

    # We don't want `Invoke-WebRequest` to throw a terminating error so wrap it in a try/catch block.
    function Invoke-WebRequest
    {
        [CmdletBinding()]
        param(
            [Uri] $Uri,
            [switch] $UseBasicParsing,
            [String] $OutFile
        )

        $numErrorsBefore = $Global:Error.Count
        try
        {
            Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
        }
        catch
        {
            Write-Error $_ -ErrorAction $ErrorActionPreference
        }

        if ($ErrorActionPreference -eq 'Ignore')
        {
            $numErrorsToClear = $Global:Error.Count - $numErrorsBefore
            for ($idx = 0; $idx -lt $numErrorsToClear; ++$idx)
            {
                $Global:Error.RemoveAt(0)
            }
        }
    }

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $ProgressPreference = 'SilentlyContinue'

    $packagesPath = Join-Path -Path $BuildRootPath -ChildPath 'packages'
    if (-not (Test-Path -Path $packagesPath))
    {
        New-Item -Path $packagesPath -ItemType 'Directory' | Out-Null
    }

    $cachePath = Join-Path -Path $BuildRootPath -ChildPath ".output\nuget"
    if( -not (Test-Path -Path $cachePath) )
    {
        New-Item -Path $cachePath -ItemType 'Directory' -Force | Out-Null
    }

    $requestedVersion = $Version
    $resolvedVersion = ''
    $failures = [Collections.ArrayList]::New()
    foreach ($pkgSource in (Get-PackageSource -ProviderName 'NuGet'))
    {
        $pkgSourceUrl = $pkgSource.Location
        $pkgIndexUrl = $pkgSourceUrl
        if ($pkgIndexUrl -notmatch '\bv3/index\.json')
        {
            $pkgIndexUrl = "${pkgIndexUrl}/v3/index.json"
        }

        $pkgIndex = $null

        Write-WhiskeyVerbose "GET ${pkgIndexUrl}"
        $pkgIndex = Invoke-RestMethod -Uri $pkgIndexUrl -ErrorAction Ignore

        # It's a v2 endpoint.
        if (-not $pkgIndex)
        {
            $path = Install-WhiskeyNuGetV2Package -Name $Name `
                                                  -Version $Version `
                                                  -PackageSource $pkgSource `
                                                  -PackagesPath $packagesPath `
                                                  -CachePath $cachePath
            if ($path)
            {
                return $path
            }

            continue
        }

        $searchResources =
            Invoke-RestMethod -Uri $pkgIndexUrl |
            Select-Object -ExpandProperty 'resources' -ErrorAction Ignore |
            Where-Object '@type' -EQ 'SearchQueryService'
        if (-not $searchResources)
        {
            [void]$failures.Add("NuGet source ""${pkgSourceUrl}"" didn't have a SearchQueryService resource")
            continue
        }

        $pkgInfo = $null
        foreach ($searchResource in $searchResources)
        {
            if (-not ($searchResource | Get-Member -Name '@id'))
            {
                $msg = "NuGet SearchQueryService resource from source ${pkgSourceUrl} doesn't have a URL " +
                       '(@id property)'
                [void]$failures.Add($msg)
                continue
            }

            $searchUrl = "$($searchResource.'@id')?q=packageid:$([uri]::EscapeDataString($Name))"
            Write-WhiskeyVerbose "GET ${searchUrl}"
            $pkgInfo =
                Invoke-RestMethod -Uri $searchUrl |
                Select-Object -ExpandProperty 'data' -ErrorAction Ignore
            if ($pkgInfo)
            {
                break
            }
        }

        if (-not $pkgInfo)
        {
            [void]$failures.Add("that package does not exist in NuGet source ${pkgSourceUrl}")
            continue
        }

        # Reset to initial version for each source.
        $requestedVersion = $Version
        if (-not $requestedVersion)
        {
            if (-not ($pkgInfo | Get-Member -Name 'version'))
            {
                [void]$failures.Add("package information from ${pkgSourceUrl} is missing version member")
                continue
            }

            $requestedVersion = $pkgInfo.version
        }

        if (-not ($pkgInfo | Get-Member -Name 'versions'))
        {
            $msg = "NuGet search request ""${searchUrl}"" is missing versions for that package"
            [void]$failures.Add($msg)
            continue
        }

        # If the version is a specific version, and not a range.
        [Version] $parsedVersion = $null
        if ([Version]::TryParse($requestedVersion, [ref]$parsedVersion))
        {
            $resolvedVersion =
                $pkgInfo.versions |
                Where-Object 'version' -EQ $requestedVersion |
                Select-Object -ExpandProperty 'version'
        }
        else
        {
            [NuGet.Versioning.VersionRange] $nugetRange = $null
            if (-not ([NuGet.Versioning.VersionRange]::TryParse($requestedVersion, [ref]$nugetRange)))
            {
                [void]$failures.Add("failed to parse ""${requestedVersion}"" as a version or NuGet version range ")
                continue
            }

            $allVersions =  [Collections.Generic.List[NuGet.Versioning.NuGetVersion]]::New()
            $pkgInfo.versions |
                Select-Object -ExpandProperty 'version' -ErrorAction Ignore |
                ForEach-Object { [NuGet.Versioning.NuGetVersion]::New($_) } |
                ForEach-Object { $allVersions.Add($_) }

            $resolvedVersion = $nuGetRange.FindBestMatch($allVersions)
        }

        if (-not $resolvedVersion)
        {
            [void]$failures.Add("there is no version of that packages that satisfies ""${requestedVersion}""")
            continue
        }

        if ($resolvedVersion -ne $requestedVersion)
        {
            $msg = "Resolved NuGet package ${Name} version ""${requestedVersion}"" to ""${resolvedVersion}"" from " +
                   "source ${pkgSourceUrl}."
            Write-WhiskeyVerbose $msg
        }

        $pkgBaseName = "${Name}.$($resolvedVersion -replace '\+.*$', '')"
        $pkgCachePath = Join-Path -Path $cachePath -ChildPath $pkgBaseName
        if( -not (Test-Path -Path $pkgCachePath) )
        {
            New-Item -Path $pkgCachePath -ItemType 'Directory' -Force | Out-Null
        }

        $nupkgPath = Join-Path -Path $pkgCachePath -ChildPath "${pkgBaseName}.nupkg"

        if( -not (Test-Path -Path $nupkgPath) )
        {
            $pkgRegUrl = $pkgInfo | Select-Object -ExpandProperty 'registration' -ErrorAction Ignore
            if (-not ($pkgRegUrl))
            {
                [void]$failures.Add("that package's registration URL is missing from NuGet source ${pkgSourceUrl}")
                continue
            }

            Write-WhiskeyVerbose "GET ${pkgRegUrl}"
            $pkgReg = Invoke-RestMethod -Uri $pkgRegUrl
            if (-not $pkgReg)
            {
                [void]$failures.Add("failed to download that packages's registration information from ${pkgRegUrl}")
                continue
            }

            $pkgRegItems =
                $pkgReg |
                Select-Object -ExpandProperty 'items' -ErrorAction Ignore |
                Select-Object -ExpandProperty 'items' -ErrorAction Ignore

            # Results are paged.
            if (-not $pkgRegItems)
            {
                $pkgRegItems =
                    $pkgReg |
                    Select-Object -ExpandProperty 'items' -ErrorAction Ignore |
                    Select-Object -ExpandProperty '@id' -ErrorAction Ignore |
                    ForEach-Object {
                        Write-WhiskeyVerbose "GET ${_}"
                        Invoke-RestMethod -Uri $_
                    } |
                    Select-Object -ExpandProperty 'items' -ErrorAction Ignore

                if (-not $pkgRegItems)
                {
                    [void]$failures.Add("failed to page that package's registration information from ${pkgRegUrl}")
                    continue
                }
            }

            $pkgVersionInfo =
                    $pkgRegItems |
                    Where-Object { $_ | Get-Member 'catalogEntry' } |
                    Where-Object { $_.catalogEntry.version -EQ $resolvedVersion }

            if (-not $pkgVersionInfo)
            {
                $msg = "that package is missing from ${pkgRegUrl}"
                [void]$failures.Add($msg)
                continue
            }

            $pkgDownloadUrl = $pkgVersionInfo | Select-Object -ExpandProperty 'packageContent' -ErrorAction Ignore
            if (-not $pkgDownloadUrl)
            {
                [void]$failures.Add("that package is missing download URL from ${pkgRegUrl}")
                continue
            }

            $numTries = 6
            $waitMilliseconds = 100
            for ($idx = 0; $idx -lt $numTries; ++$idx)
            {
                $destinationPath = [IO.Path]::GetFileNameWithoutExtension($nupkgPath)
                $destinationPath = Join-Path -Path ($packagesPath | Resolve-Path -Relative) -ChildPath $destinationPath
                Write-WhiskeyInfo "Saving NuGet package ${Name} ${resolvedVersion} to ""${destinationPath}""."
                Write-WhiskeyVerbose "GET ${pkgDownloadUrl}"
                Invoke-WebRequest -UseBasicParsing -Uri $pkgDownloadUrl -OutFile $nupkgPath

                if( (Test-Path -Path $nupkgPath) )
                {
                    break
                }

                Start-Sleep -Milliseconds $waitMilliseconds
                $waitMilliseconds = $waitMilliseconds * 2
            }

            if( -not (Test-Path -Path $nupkgPath) )
            {
                [void]$failures.Add("downloading from ${pkgDownloadUrl} failed")
                continue
            }

            # Now, resolve and download dependencies.
            $deps =
                $pkgVersionInfo.catalogEntry |
                Select-Object -ExpandProperty 'dependencyGroups' -ErrorAction Ignore |
                Select-Object -ExpandProperty 'dependencies' -ErrorAction Ignore
            foreach ($dep in $deps)
            {
                $depId = $dep | Select-Object -ExpandProperty 'id' -ErrorAction Ignore
                if (-not $depId)
                {
                    [void]$failures.Add("a dependency listed in ${pkgRegUrl} is missing its id")
                    continue
                }
                $depRange = $dep | Select-Object -ExpandProperty 'range' -ErrorAction Ignore
                if (-not $depRange)
                {
                    [void]$failures.Add("depedency ${depId} in ${pkgRegUrl} is missing its version range")
                    continue
                }

                Install-WhiskeyNuGetPackage -Name $depId -Version $depRange -BuildRootPath $BuildRootPath | Out-Null
            }
        }

        foreach ($nupkgInfo in (Get-ChildItem -Path $pkgCachePath -Filter '*.nupkg'))
        {
            $pkgPath = Join-Path -Path $packagesPath -ChildPath $nupkgInfo.BaseName
            if (-not (Test-Path -Path $pkgPath))
            {
                New-Item -Path $pkgPath -ItemType 'Directory' -Force | Out-Null
            }

            if (-not (Get-ChildItem -LiteralPath $pkgPath))
            {
                Write-WhiskeyVerbose "Extracting ""$($nupkgInfo.Name)"" to ""$($pkgPath | Resolve-Path -Relative)""."
                Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
                [IO.Compression.ZipFile]::ExtractToDirectory($nupkgInfo.FullName, $pkgPath)
            }
        }

        return Join-Path -Path $packagesPath -ChildPath $pkgBaseName
    }

    $preamble = "Failed to install latest version of NuGet package ${Name}"
    if ($resolvedVersion -or $requestedVersion)
    {
        $versionMsg = $resolvedVersion
        if (-not $resolvedVersion)
        {
            $versionMsg = $requestedVersion
        }
        $preamble = "Failed to install NuGet package ${Name} ${versionMsg}"
    }

    foreach ($reason in $failures)
    {
        $msg = "${preamble} because ${reason}."
        Write-WhiskeyError $msg
    }
}