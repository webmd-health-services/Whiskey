
function Install-NodeJsPackage
{
    [CmdletBinding()]
    param(
        # Path to a downloaded Node.js .zip/.tgz package.
        [Parameter(Mandatory)]
        [String] $PackagePath,

        # The directory where Node.js should be installed.
        [Parameter(Mandatory)]
        [String] $DestinationPath,

        [String] $NpmVersion
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if (Test-Path -Path $DestinationPath)
    {
        Remove-WhiskeyFileSystemItem -Path $DestinationPath
    }

    if ($IsWindows)
    {
        # Windows/.NET can't handle the long paths in the Node package, so on that platform, we need to download
        # 7-zip because it can handle long paths.
        $7zipPackageRoot = Install-WhiskeyTool -Name '7-Zip.CommandLine' `
                                                -ProviderName 'NuGet' `
                                                -Version '18.*' `
                                                -InstallRoot $TaskContext.BuildRoot
        $7z = Join-Path -Path $7zipPackageRoot -ChildPath 'tools\x64\7za.exe' -Resolve -ErrorAction Stop

        $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
        $outputDirectoryName = $archive.Entries[0].FullName
        $archive.Dispose()
        $outputDirectoryName =
            $outputDirectoryName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $extractDirPath = Join-Path -Path ($DestinationPath | Split-Path -Parent) -ChildPath $outputDirectoryName

        Write-WhiskeyVerbose -Message ('{0} x {1} -o{2} -y' -f $7z,$PackagePath,$extractDirPath)
        & $7z -spe 'x' $PackagePath ('-o{0}' -f $extractDirPath) '-y' | Write-WhiskeyVerbose

        # We use New-TimeSpan so we can mock it and wait for our simulated anti-virus process to lock a
        # file (i.e. so we can test that this wait logic works).
        $maxTime = New-TimeSpan -Seconds 10
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $exists = $false
        $lastError = $null
        $nodeDirectoryName = $DestinationPath | Split-Path -Leaf
        Write-WhiskeyDebug "Renaming $($extractDirPath | Format-Path) -> $($nodeDirectoryName | Format-Path)."
        do
        {
            Rename-Item -Path $extractDirPath -NewName $nodeDirectoryName -ErrorAction SilentlyContinue
            $exists = Test-Path -Path $DestinationPath -PathType Container

            if( $exists )
            {
                Write-WhiskeyDebug "Rename succeeded."
                break
            }

            $lastError = $Global:Error | Select-Object -First 1
            Write-WhiskeyDebug -Message "Rename failed: $($lastError)"

            $Global:Error.RemoveAt(0)
            Start-Sleep -Seconds 1
        }
        while( $timer.Elapsed -lt $maxTime )

        if (-not $exists)
        {
            $msg = "Failed to install Node.js ${Version} to $($DestinationPath | Format-Path) because renaming " +
                    "directory $($outputDirectoryName | Format-Path) to $($nodeDirectoryName | Format-Path) " +
                    "failed: $($lastError)"
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }

    }
    else
    {
        if( -not (Test-Path -Path $DestinationPath -PathType Container) )
        {
            New-Item -Path $DestinationPath -ItemType 'Directory' -Force | Out-Null
        }

        $msg = "tar -xJf $($PackagePath | Format-Path) -C $($DestinationPath | Format-Path) --strip-components=1"
        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
        tar -xJf $PackagePath -C $DestinationPath '--strip-components=1' | Write-WhiskeyVerbose
        if ($LASTEXITCODE)
        {
            $msg = "Failed to extract Node.js ${Version} package $($PackagePath | Format-Path) to " +
                    "$($DestinationPath | Format-Path)."
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }
    }
}

