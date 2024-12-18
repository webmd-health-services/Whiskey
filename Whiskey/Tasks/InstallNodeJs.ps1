function Install-Node
{
    [Whiskey.Task('InstallNodeJs')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [String] $PackageJsonPath,

        [String] $Version,

        [String] $NpmVersion,

        [Alias('NodePath')]
        [String] $Path,

        [String] $Cpu
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    function Resolve-NodeJsVersion
    {
        [CmdletBinding()]
        param(
            [String] $Version
        )

        $nodeVersions = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | ForEach-Object { $_ }
        $nodeVersion =
            $nodeVersions |
            Where-Object { ($_ | Get-Member 'lts') -and $_.lts } |
            Select-Object -First 1

        if ($Version)
        {
            $versionWildcard = $Version
            if ($Version -match '^\d+(\.\d+)?$')
            {
                $versionWildcard = "${Version}.*"
            }

            $nodeVersion = $nodeVersions | Where-Object 'version' -Like "v${versionWildcard}" | Select-Object -First 1
            if (-not $nodeVersion)
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message "Node v${Version} does not exist."
                return
            }
        }

        return $nodeVersion.version
    }

    function Save-NodeJsPackage
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Version
        )

        $platform = 'win'
        $packageExtension = 'zip'
        if ($IsLinux)
        {
            $platform = 'linux'
            $packageExtension = 'tar.xz'
        }
        elseif ($IsMacOS)
        {
            $platform = 'darwin'
            $packageExtension = 'tar.gz'
        }

        if ($Cpu)
        {
            $arch = $Cpu
        }
        else
        {
            $arch = 'x86'
            if ([Environment]::Is64BitOperatingSystem)
            {
                $arch = 'x64'
            }
        }

        $extractedDirName = "node-${Version}-${platform}-${arch}"
        $filename = "${extractedDirName}.${packageExtension}"

        $pkgChecksum = ''
        $checksumsUrl = "https://nodejs.org/dist/${Version}/SHASUMS256.txt"
        try
        {
            $pkgChecksum =
                Invoke-WebRequest -Uri $checksumsUrl -ErrorAction Ignore |
                Select-Object -ExpandProperty 'Content' |
                ForEach-Object { $_ -split '\r?\n' } |
                Where-Object { $_ -match "^([^ ]+) +$([regex]::Escape($filename))$" } |
                ForEach-Object { $Matches[1] } |
                Select-Object -First 1

            if (-not $pkgChecksum)
            {
                $msg = "Node.js package will not be validated because the $($filename | Format-Path) package's checksum is " +
                       "missing from ${checksumsUrl}."
                Write-WhiskeyWarning -Context $TaskContext -Message $msg
            }
        }
        catch
        {
            $msg = "Node.js package will not be validated because the request to download the ${Version} checksums " +
                   "from ${checksumsUrl} failed: ${_}."
            Write-WhiskeyWarning -Context $TaskContext -Message $msg
        }

        $outputDirPath = $TaskContext.OutputDirectory
        $nodeZipFilePath = Join-Path -Path $outputDirPath -ChildPath $filename
        if ((Test-Path -Path $nodeZipFilePath))
        {
            $actualChecksum = Get-FileHash -Path $nodeZipFilePath -Algorithm SHA256
            if ($pkgChecksum -and $pkgChecksum -eq $actualChecksum.Hash)
            {
                return $nodeZipFilePath
            }

            Remove-Item -Path $nodeZipFilePath
        }

        $pkgUrl = "https://nodejs.org/dist/${Version}/${filename}"

        if (-not (Test-Path -Path $outputDirPath))
        {
            Write-WhiskeyDebug -Message "Creating output directory $($outputDirPath | Format-Path)."
            New-Item -Path $outputDirPath -ItemType 'Directory' -Force | Out-Null
        }

        try
        {
            Invoke-WebRequest -Uri $pkgUrl -OutFile $nodeZipFilePath | Out-Null
        }
        catch
        {
            $responseInfo = ''
            $notFound = $false
            if( $_.Exception | Get-Member -Name 'Response' )
            {
                $responseStatus = $_.Exception.Response.StatusCode
                $responseInfo = ' Received a {0} ({1}) response.' -f $responseStatus,[int]$responseStatus
                if( $responseStatus -eq [Net.HttpStatusCode]::NotFound )
                {
                    $notFound = $true
                }
            }
            else
            {
                Write-WhiskeyError -Message "Exception downloading ${pkgUrl}: $($_)"
                $responseInfo = ' Please see previous error for more information.'
                return
            }

            $errorMsg = "Failed to download Node ${Version}) from ${pkgUrl}.$($responseInfo)"
            if( $notFound )
            {
                $errorMsg = "$($errorMsg) It looks like this version of Node wasn't packaged as a ZIP file. " +
                            'Please use Node v4.5.0 or newer.'
            }
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $errorMsg
            return
        }

        if ($pkgChecksum)
        {
            $actualChecksum = Get-FileHash -Path $nodeZipFilePath -Algorithm SHA256
            if ($pkgChecksum -ne $actualChecksum.Hash)
            {
                $msg = "Failed to install Node.js ${Version} because the SHA256 checksum of the file downloaded " +
                       "from ${pkgUrl}, ${actualChecksum}, doesn't match the expected checksum, ${pkgChecksum}."
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                return
            }
        }

        return $nodeZipFilePath
    }

    function Install-NodeJsPackage
    {
        [CmdletBinding()]
        param(
            # The directory where Node.js should be installed.
            [Parameter(Mandatory)]
            [String] $PackagePath,

            [Parameter(Mandatory)]
            [String] $DestinationPath
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

    $nodeSource = ''
    $npmSource = ''
    $whiskeyYmlPath = $TaskContext.ConfigurationPath | Resolve-WhiskeyRelativePath

    if ($Version)
    {
        $nodeSource = $whiskeyYmlPath
    }

    if ($NpmVersion)
    {
        $npmSource = $whiskeyYmlPath
    }

    if (-not $Version)
    {
        $nodeVersionPath = Join-Path -Path $TaskContext.BuildRoot -ChildPath '.node-version'
        if ((Test-Path -Path $nodeVersionPath -PathType Leaf))
        {
            $nodeSource = $nodeVersionPath | Resolve-WhiskeyRelativePath
            $Version = Get-Content -Path $nodeVersionPath -ReadCount 1
        }
    }

    if (-not $Version -or -not $NpmVersion)
    {
        if (-not $PackageJsonPath)
        {
            $PackageJsonPath = 'package.json'
        }

        $PackageJsonPath = $PackageJsonPath | Resolve-WhiskeyTaskPath -PropertyName 'PackageJsonPath' `
                                                                      -OnlySinglePath `
                                                                      -PathType File `
                                                                      -TaskContext $TaskContext `
                                                                      -AllowNonexistent `
                                                                      -ErrorAction Ignore

        if ($PackageJsonPath -and (Test-Path -Path $PackageJsonPath -PathType Leaf))
        {
            $whiskeyPkgCfg =
                Get-Content -Path $PackageJsonPath |
                ConvertFrom-Json |
                Select-Object -ExpandProperty 'whiskey' -ErrorAction Ignore
            if (-not $Version)
            {
                $Version = $whiskeyPkgCfg | Select-Object -ExpandProperty 'node' -ErrorAction Ignore
                if ($Version)
                {
                    $nodeSource = $PackageJsonPath
                }
            }

            if (-not $NpmVersion)
            {
                $NpmVersion = $whiskeyPkgCfg | Select-Object -ExpandProperty 'npm' -ErrorAction Ignore
                if ($NpmVersion)
                {
                    $npmSource = $PackageJsonPath
                }
            }
        }
    }

    if (-not $Path)
    {
        $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath '.node'
    }

    $Path = $Path | Resolve-WhiskeyTaskPath -TaskContext $TaskContext `
                                            -PropertyName 'Path' `
                                            -OnlySinglePath `
                                            -PathType Directory `
                                            -AllowNonexistent

    $Version = $Version -replace '^v',''
    $NpmVersion = $NpmVersion -replace '^v',''
    $versionToInstall = Resolve-NodeJsVersion -Version $Version
    if (-not $versionToInstall)
    {
        return
    }

    $nodeCmdName = Join-Path -Path 'bin' -ChildPath 'node'
    $npmCmdName = Join-Path -Path 'bin' -ChildPath 'npm'
    if ($IsWindows)
    {
        $nodeCmdName = 'node.exe'
        $npmCmdName = 'npm.cmd'
    }

    $installNode = $true
    $nodePath = Join-Path -Path $Path -ChildPath $nodeCmdName
    $nodePath = [IO.Path]::GetFullPath($nodePath)
    if (Test-Path -Path $nodePath -PathType Leaf)
    {
        $currentNodeVersion = & $nodePath '--version'
        if ($currentNodeVersion -eq $versionToInstall)
        {
            Write-WhiskeyVerbose "Node.js ${versionToInstall} already installed in $($Path | Format-Path)."
            $installNode = $false
        }
    }

    $nodeSourceMsg = ' (the latest active LTS version)'
    if ($nodeSource)
    {
        $nodeSourceMsg = " (version read from file $($nodeSource | Format-Path))"
    }

    $npmSourceMsg = ''
    if ($npmSource)
    {
        $npmSourceMsg = " (version read from file $($npmSource | Format-Path))"
    }

    if ($installNode)
    {
        $pkgPath = Save-NodeJsPackage -Version $versionToInstall
        if (-not $pkgPath)
        {
            return
        }

        $msg = "Installing Node.js ${versionToInstall} to $($Path | Format-Path)${nodeSourceMsg}."
        Write-WhiskeyInfo -Context $TaskContext -Message $msg

        $installPath = Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
        $installPath = [IO.Path]::GetFullPath($installPath)
        Install-NodeJsPackage -PackagePath $pkgPath -DestinationPath $installPath
    }

    if (-not (Test-Path -Path $nodePath -PathType Leaf))
    {
        return
    }

    $pathItems = $env:Path -split ([regex]::Escape([IO.Path]::PathSeparator))
    $nodeDirPath = $nodePath | Split-Path -Parent
    if ($pathItems -notcontains $nodeDirPath)
    {
        $msg = "Adding $($nodeDirPath | Format-Path) to PATH environment variable."
        Write-WhiskeyInfo -Context $TaskContext -Message $msg
        $newPath = "${nodeDirPath}$([IO.Path]::PathSeparator)${env:PATH}"
        [Environment]::SetEnvironmentVariable('PATH', $newPath, [EnvironmentVariableTarget]::Process)
    }

    if ($NpmVersion)
    {
        $npmPath = Join-Path -Path $Path -ChildPath $npmCmdName
        $currentNpmVersion = & $npmPath '--version'
        if ($NpmVersion -ne $currentNpmVersion)
        {
            $msg = "Installing npm@${NpmVersion}${npmSourceMsg}."
            Write-WhiskeyInfo -Context $TaskContext -Message $msg
            & $npmPath install "npm@${NpmVersion}" '-g'
        }
    }
}