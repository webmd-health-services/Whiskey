
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

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    # Sometimes finding packages can be flaky, so we try multiple times.
    $numErrors = $Global:Error.Count
    $numTries = 6
    $waitMilliseconds = 100
    $allPkgs = @()
    $pkgMgmtErrors = @{}
    for( $idx = 0; $idx -lt $numTries; ++$idx )
    {
        $allPkgs =
            Find-Package -Name $Name `
                         -ProviderName 'NuGet' `
                         -AllVersions `
                         -ErrorAction SilentlyContinue `
                         -ErrorVariable 'pkgMgmtErrors' |
            Where-Object { $_ -notmatch '-' }

        if( $allPkgs )
        {
            Write-WhiskeyVerbose "Found $(($allPkgs | Measure-Object).Count) $($Name) packages:"
            foreach ($pkg in $allPkgs)
            {
                Write-WhiskeyVerbose "  $($pkg.Name) $($pkg.Version) from $($pkg.Source) [$($pkg.GetType().FullName)]"
            }
            break
        }

        Start-Sleep -Milliseconds $waitMilliseconds
        $waitMilliseconds = $waitMilliseconds + 2
    }

    if (-not $allPkgs)
    {
        $pkgMgmtErrors | Write-Error

        $msg = "NuGet package $($Name) $($Version) does not exist or search request failed."
        Write-WhiskeyError -Message $msg
        return
    }

    for ($idx = 0; $idx -lt $Global:Error.Count - $numErrors; ++$idx)
    {
        $Global:Error.RemoveAt(0)
    }

    $pkg = $allPkgs | Select-Object -First 1
    if ($Version)
    {
        $pkgVersions = $allPkgs | Where-Object 'Version' -Like $Version
        if (-not $pkgVersions)
        {
            # Some package versions have build metadata at the end.
            $pkgVersions = $allPkgs | Where-Object 'Version' -Like "$($Version)+*"
        }

        if (-not $pkgVersions)
        {
            "Failed to install NuGet package $($Name) $($Version) because that version does not exist. Available " +
                'versions are:' + [Environment]::NewLine +
                [Environment]::NewLine +
                "* $(($allPkgs | Select-Object -ExpandProperty 'Version') -join "$([Environment]::NewLine)* ")" |
                Write-WhiskeyError
            return
        }

        Write-WhiskeyVerbose "Found $(($pkgVersions | Measure-Object).Count) $($Name) $($Version) packages:"
        foreach ($pkg in $pkgVersions)
        {
            Write-WhiskeyVerbose "  $($pkg.Name) $($pkg.Version) from $($pkg.Source) [$($pkg.GetType().FullName)]"
        }

        $pkg = $pkgVersions | Select-Object -First 1
    }

    "Found package $($pkg.Name) $($pkg.Version) from $($pkg.Source)." | Write-WhiskeyVerbose

    $pkgBaseName = "$($Name).$($pkg.Version -replace '\+.*$', '')"

    # Save-Module downloads dependencies, too. Save everything for a package into its own directory so we know which
    # packages to install as dependencies.
    $cachePath = Join-Path -Path $BuildRootPath -ChildPath ".output\nuget\$($pkgBaseName)"
    if( -not (Test-Path -Path $cachePath) )
    {
        New-Item -Path $cachePath -ItemType 'Directory' | Out-Null
    }

    $nupkgPath = Join-Path -Path $cachePath -ChildPath "$($pkgBaseName).nupkg"
    if( -not (Test-Path -Path $nupkgPath) )
    {
        $waitMilliseconds = 100
        $numErrors = $Global:Error.Count
        $pkgMgmtErrors = @()
        for( $idx = 0; $idx -lt $numTries; ++$idx )
        {
            Write-WhiskeyInfo -Message "Downloading NuGet package $($pkg.Name) $($pkg.Version)."
            $pkg |
                Save-Package -Path $cachePath -ErrorAction SilentlyContinue -ErrorVariable 'pkgMgmtErrors' -Force |
                Out-Null

            if( (Test-Path -Path $nupkgPath) )
            {
                break
            }

            Start-Sleep -Milliseconds $waitMilliseconds
            $waitMilliseconds = $waitMilliseconds * 2
        }

        if( -not (Test-Path -Path $nupkgPath) )
        {
            $pkgMgmtErrors | Write-Error
            $msg = "Failed to download NuGet package $($pkg.Name) $($pkg.Version)."
            Write-WhiskeyError -Message $msg
            return
        }

        for( $idx = 0; $idx -lt $Global:Error.Count - $numErrors; ++$idx )
        {
            $Global:Error.RemoveAt(0)
        }
    }

    $packagesPath = Join-Path -Path $BuildRootPath -ChildPath 'packages'

    # Install the package and all its dependencies into 'packages'.
    foreach( $pkgInfo in (Get-ChildItem -Path $cachePath -Filter '*.nupkg') )
    {
        $pkgPath = Join-Path -Path $packagesPath -ChildPath $pkgInfo.BaseName
        if( -not (Test-Path -Path $pkgPath) )
        {
            New-Item -Path $pkgPath -ItemType 'Directory' -Force | Out-Null
        }

        if( -not (Get-ChildItem -LiteralPath $pkgPath) )
        {
            Write-WhiskeyInfo -Message "Extracting ""$($pkgInfo.Name)"" to ""$($pkgPath | Resolve-Path -Relative)""."
            Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
            [IO.Compression.ZipFile]::ExtractToDirectory($pkgInfo.FullName, $pkgPath)
        }
    }

    return Join-Path -Path $packagesPath -ChildPath $pkgBaseName
}