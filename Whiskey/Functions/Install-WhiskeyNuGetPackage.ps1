
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

    Import-WhiskeyPowerShellModule -Name 'PackageManagement' -PSModulesRoot $BuildRootPath

    # Sometimes finding packages can be flaky, so we try multiple times.
    $numErrors = $Global:Error.Count
    $numTries = 6
    $waitMilliseconds = 100
    $pkgVersions = @()
    $pkgMgmtErrors = @{}
    for( $idx = 0; $idx -lt $numTries; ++$idx )
    {
        $pkgVersions =
            Find-Package -Name $Name `
                         -ProviderName 'NuGet' `
                         -AllVersions `
                         -ErrorAction SilentlyContinue `
                         -ErrorVariable 'pkgMgmtErrors' |
            Where-Object { $_ -notmatch '-' }
        if( $pkgVersions )
        {
            break
        }

        Start-Sleep -Milliseconds $waitMilliseconds
        $waitMilliseconds = $waitMilliseconds + 2
    }

    if( -not $pkgVersions )
    {
        $pkgMgmtErrors | Write-Error

        $msg = "NuGet package $($Name) $($Version) does not exist or search request failed."
        Write-WhiskeyError -Message $msg
        return
    }

    for( $idx = 0; $idx -lt $Global:Error.Count - $numErrors; ++$idx )
    {
        $Global:Error.RemoveAt(0)
    }

    if( $Version )
    {
        $pkgVersions = $pkgVersions | Where-Object 'Version' -Like $Version
    }

    $pkg = $pkgVersions | Select-Object -First 1

    $cachePath = Join-Path -Path $BuildRootPath -ChildPath '.output\nuget'
    if( -not (Test-Path -Path $cachePath) )
    {
        New-Item -Path $cachePath -ItemType 'Directory' | Out-Null
    }

    $pkgBaseName = "$($Name).$($pkg.Version)"

    $nupkgPath = Join-Path -Path $cachePath -ChildPath "$($pkgBaseName).nupkg"
    if( -not (Test-Path -Path $nupkgPath) )
    {
        $waitMilliseconds = 100
        $numErrors = $Global:Error.Count
        $pkgMgmtErrors = @()
        for( $idx = 0; $idx -lt $numTries; ++$idx )
        {
            $pkg | Save-Package -Path $cachePath -ErrorAction SilentlyContinue -ErrorVariable 'pkgMgmtErrors' | Out-Null

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

    $pkgPath = Join-Path -Path $BuildRootPath -ChildPath "packages\$($pkgBaseName)"
    if( -not (Test-Path -Path $pkgPath)  )
    {
        New-Item -Path $pkgPath -ItemType 'Directory' -Force | Out-Null
    }

    if( -not (Get-ChildItem -LiteralPath $pkgPath) )
    {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [IO.Compression.ZipFile]::ExtractToDirectory($nupkgPath, $pkgPath)
    }

    return $pkgPath
}