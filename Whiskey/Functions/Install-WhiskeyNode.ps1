
function Install-WhiskeyNode
{
    [CmdletBinding()]
    param(
        # The directory where Node should be installed. Will actually be installed into
        # `Join-Path -Path $InstallRootPath -ChildPath '.node'`.
        [Parameter(Mandatory)]
        [String] $InstallRootPath,

        # The directory where the Node.js package file should be downloaded.
        [Parameter(Mandatory)]
        [String] $OutFileRootPath,

        # Are we running in clean mode? If so, don't re-install the tool.
        [switch] $InCleanMode,

        # The version of Node to install. If not provided, will use the version defined in the package.json file. If
        # that isn't supplied, will install the latest LTS version.
        [String] $Version,

        [String] $NodeDirectoryName = '.node'
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRootPath `
                                        -NodeDirectoryName $NodeDirectoryName `
                                        -ErrorAction Ignore

    if( $InCleanMode )
    {
        if( $nodePath )
        {
            return $nodePath
        }
        return
    }

    $npmVersionToInstall = $null
    $nodeVersionToInstall = $null
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    $nodeVersions = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | ForEach-Object { $_ }
    if( $Version )
    {
        $nodeVersionToInstall =
            $nodeVersions |
            Where-Object { $_.version -like 'v{0}' -f $Version } |
            Select-Object -First 1
        if( -not $nodeVersionToInstall )
        {
            throw ('Node v{0} does not exist.' -f $Version)
        }
    }
    else
    {
        $packageJsonPath = Join-Path -Path (Get-Location).ProviderPath -ChildPath 'package.json'
        if( -not (Test-Path -Path $packageJsonPath -PathType Leaf) )
        {
            $packageJsonPath = Join-Path -Path $InstallRootPath -ChildPath 'package.json'
        }

        if( (Test-Path -Path $packageJsonPath -PathType Leaf) )
        {
            Write-WhiskeyVerbose -Message ('Reading ''{0}'' to determine Node and NPM versions to use.' -f $packageJsonPath)
            $packageJson = Get-Content -Raw -Path $packageJsonPath | ConvertFrom-Json
            if( $packageJson -and ($packageJson | Get-Member 'engines') )
            {
                if( ($packageJson.engines | Get-Member 'node') -and $packageJson.engines.node -match '(\d+\.\d+\.\d+)' )
                {
                    $nodeVersionToInstall = 'v{0}' -f $Matches[1]
                    $nodeVersionToInstall =  $nodeVersions |
                                                Where-Object { $_.version -eq $nodeVersionToInstall } |
                                                Select-Object -First 1
                }

                if( ($packageJson.engines | Get-Member 'npm') -and $packageJson.engines.npm -match '(\d+\.\d+\.\d+)' )
                {
                    $npmVersionToInstall = $Matches[1]
                }
            }
        }
    }

    if( -not $nodeVersionToInstall )
    {
        $nodeVersionToInstall = $nodeVersions |
                                    Where-Object { ($_ | Get-Member 'lts') -and $_.lts } |
                                    Select-Object -First 1
    }

    if( -not $npmVersionToInstall )
    {
        $npmVersionToInstall = $nodeVersionToInstall.npm
    }

    $installNode = $false
    if( $nodePath )
    {
        $currentNodeVersion = & $nodePath '--version'
        if( $currentNodeVersion -ne $nodeVersionToInstall.version )
        {
            Uninstall-WhiskeyNode -InstallRoot $InstallRootPath
            $installNode = $true
        }
    }
    else
    {
        $installNode = $true
    }

    $nodeRoot = Join-Path -Path $InstallRootPath -ChildPath $NodeDirectoryName

    $platform = 'win'
    $packageExtension = 'zip'
    if( $IsLinux )
    {
        $platform = 'linux'
        $packageExtension = 'tar.xz'
    }
    elseif( $IsMacOS )
    {
        $platform = 'darwin'
        $packageExtension = 'tar.gz'
    }

    $extractedDirName = 'node-{0}-{1}-x64' -f $nodeVersionToInstall.version,$platform
    $filename = '{0}.{1}' -f $extractedDirName,$packageExtension

    if( $installNode )
    {
        $nodeZipFilePath = Join-Path -Path $OutFileRootPath -ChildPath $filename
        if( -not (Test-Path -Path $nodeZipFilePath -PathType Leaf) )
        {
            $uri = 'https://nodejs.org/dist/{0}/{1}' -f $nodeVersionToInstall.version,$filename

            if( -not (Test-Path -Path $OutFileRootPath) )
            {
                Write-WhiskeyDebug -Message "Creating output directory ""$($OutFileRootPath)""."
                New-Item -Path $OutFileRootPath -ItemType 'Directory' -Force | Out-Null
            }

            $preExistingPkgPath =
                Join-Path -Path $OutFileRootPath -ChildPath "node-*-*-x64.$($packageExtension)"
            if( (Test-Path -Path $preExistingPkgPath) )
            {
                Remove-Item -Path $preExistingPkgPath -Force -ErrorAction Ignore
            }

            try
            {
                $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
                Invoke-WebRequest -Uri $uri -OutFile $nodeZipFilePath -UseBasicParsing
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
                    Write-WhiskeyError -Message "Exception downloading ""$($uri)"": $($_)"
                    $responseInfo = ' Please see previous error for more information.'
                }

                $errorMsg = "Failed to download Node $($nodeVersionToInstall.version) from $($uri).$($responseInfo)"
                if( $notFound )
                {
                    $errorMsg = "$($errorMsg) It looks like this version of Node wasn't packaged as a ZIP file. " +
                                'Please use Node v4.5.0 or newer.'
                }
                Write-WhiskeyError -Message $errorMsg -ErrorAction Stop
                return
            }
        }

        if( $IsWindows )
        {
            # Windows/.NET can't handle the long paths in the Node package, so on that platform, we need to download
            # 7-zip because it can handle long paths.
            $7zipPackageRoot = Install-WhiskeyTool -Name '7-Zip.CommandLine' `
                                                   -ProviderName 'NuGet' `
                                                   -Version '18.*' `
                                                   -InstallRoot $InstallRootPath
            $7z = Join-Path -Path $7zipPackageRoot -ChildPath 'tools\x64\7za.exe' -Resolve -ErrorAction Stop

            $archive = [IO.Compression.ZipFile]::OpenRead($nodeZipFilePath)
            $outputDirectoryName = $archive.Entries[0].FullName
            $archive.Dispose()
            $outputDirectoryName =
                $outputDirectoryName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $outputRoot = Join-Path -Path $InstallRootPath -ChildPath $outputDirectoryName

            Write-WhiskeyVerbose -Message ('{0} x {1} -o{2} -y' -f $7z,$nodeZipFilePath,$outputRoot)
            & $7z -spe 'x' $nodeZipFilePath ('-o{0}' -f $outputRoot) '-y' | Write-WhiskeyVerbose

            # We use New-TimeSpan so we can mock it and wait for our simulated anti-virus process to lock a
            # file (i.e. so we can test that this wait logic works).
            $maxTime = New-TimeSpan -Seconds 10
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $exists = $false
            $lastError = $null
            Write-WhiskeyDebug "Renaming ""$($outputRoot)"" -> ""${NodeDirectoryName}""."
            do
            {
                Rename-Item -Path $outputRoot -NewName $NodeDirectoryName -ErrorAction SilentlyContinue
                $exists = Test-Path -Path $nodeRoot -PathType Container

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

            if( -not $exists )
            {
                $msg = "Failed to install Node to ""$($nodeRoot)"" because renaming directory " +
                       """$($outputDirectoryName)"" to ""${NodeDirectoryName}"" failed: $($lastError)"
                Write-WhiskeyError -Message $msg
            }

        }
        else
        {
            if( -not (Test-Path -Path $nodeRoot -PathType Container) )
            {
                New-Item -Path $nodeRoot -ItemType 'Directory' -Force | Out-Null
            }

            Write-WhiskeyVerbose -Message ('tar -xJf "{0}" -C "{1}" --strip-components=1' -f $nodeZipFilePath,$nodeRoot)
            tar -xJf $nodeZipFilePath -C $nodeRoot '--strip-components=1' | Write-WhiskeyVerbose
            if( $LASTEXITCODE )
            {
                Write-WhiskeyError -Message ('Failed to extract Node.js {0} package "{1}" to "{2}".' -f $nodeVersionToInstall.version,$nodeZipFilePath,$nodeRoot)
                return
            }
        }

        $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRootPath `
                                            -NodeDirectoryName $NodeDirectoryName `
                                            -ErrorAction Stop
    }

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -NodeRootPath $nodeRoot -ErrorAction Stop
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
    $npmVersion = & $nodePath $npmPath '--version'
    if( $npmVersion -ne $npmVersionToInstall )
    {
        Write-WhiskeyInfo ('Installing npm@{0}.' -f $npmVersionToInstall)
        # Bug in NPM 5 that won't delete these files in the node home directory.
        Get-ChildItem -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Include 'npm.cmd','npm','npx.cmd','npx' | Remove-Item
        & $nodePath $npmPath 'install' ('npm@{0}' -f $npmVersionToInstall) '-g'
        if( $LASTEXITCODE )
        {
            "Failed to update to NPM $($npmVersionToInstall). See previous output for details." |
                Write-WhiskeyError
        }
    }

    return $nodePath
}
