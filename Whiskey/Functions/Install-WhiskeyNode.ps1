
function Install-WhiskeyNode
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The directory where Node should be installed. Will actually be installed into `Join-Path -Path $InstallRoot -ChildPath '.node'`.
        [String]$InstallRoot,

        # Are we running in clean mode? If so, don't re-install the tool.
        [switch]$InCleanMode,

        # The version of Node to install. If not provided, will use the version defined in the package.json file. If that isn't supplied, will install the latest LTS version.
        [String]$Version,

        [Parameter(Mandatory)]
        # The build output directory
        [String]$OutputPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRoot -ErrorAction Ignore

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
        $nodeVersionToInstall = $nodeVersions | Where-Object { $_.version -like 'v{0}' -f $Version } | Select-Object -First 1
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
            $packageJsonPath = Join-Path -Path $InstallRoot -ChildPath 'package.json'
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
            Uninstall-WhiskeyNode -InstallRoot $InstallRoot
            $installNode = $true
        }
    }
    else
    {
        $installNode = $true
    }

    $nodeDirectoryName = '.node'
    $nodeRoot = Join-Path -Path $InstallRoot -ChildPath $nodeDirectoryName

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
    $nodeZipFile = Join-Path -Path $OutputPath -ChildPath $filename
    if( -not (Test-Path -Path $nodeZipFile -PathType Leaf) )
    {
        $uri = 'https://nodejs.org/dist/{0}/{1}' -f $nodeVersionToInstall.version,$filename

        if( $installNode )
        {
            if( -not (Test-Path -Path $OutputPath) )
            {
                Write-WhiskeyDebug -Message "Creating output directory ""$($OutputPath)""."
                New-Item -Path $OutputPath -ItemType 'Directory' -Force | Out-Null
            }

            try
            {
                $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
                Invoke-WebRequest -Uri $uri -OutFile $nodeZipFile
            }
            catch
            {
                $responseInfo = ''
                $notFound = $false
                if( $_.Exception | Get-Member -Name 'Response' )
                {
                    $responseStatus = $_.Exception.Response.StatusCode
                    $responseInfo = 'Received a {0} ({1}) response.' -f $responseStatus,[int]$responseStatus
                    if( $responseStatus -eq [Net.HttpStatusCode]::NotFound )
                    {
                        $notFound = $true
                    }
                }
                else
                {
                    Write-WhiskeyError -Message "Exception downloading ""$($uri)"": $($_)"
                    $responseInfo = 'Please see previous error for more information.'
                }

                $errorMsg = 'Failed to download Node {0} from {1}.{2}' -f $nodeVersionToInstall.version,$uri,$responseInfo
                if( $notFound )
                {
                    $errorMsg = '{0} It looks like this version of Node wasn''t packaged as a ZIP file. Please use Node v4.5.0 or newer.' -f $errorMsg
                }
                Write-WhiskeyError -Message $errorMsg -ErrorAction Stop
                return
            }
        }
    }

    if( $installNode )
    {
        if( $IsWindows )
        {
            # Windows/.NET can't handle the long paths in the Node package, so on that platform, we need to download
            # 7-zip because it can handle long paths.
            $7zipPackageRoot = Install-WhiskeyTool -NuGetPackageName '7-Zip.CommandLine' -DownloadRoot $InstallRoot
            $7z = Join-Path -Path $7zipPackageRoot -ChildPath 'tools\x64\7za.exe' -Resolve -ErrorAction Stop

            $archive = [io.compression.zipfile]::OpenRead($nodeZipFile)
            $outputDirectoryName = $archive.Entries[0].FullName
            $archive.Dispose()
            $outputDirectoryName =
                $outputDirectoryName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $outputRoot = Join-Path -Path $InstallRoot -ChildPath $outputDirectoryName

            Write-WhiskeyVerbose -Message ('{0} x {1} -o{2} -y' -f $7z,$nodeZipFile,$outputRoot)
            & $7z -spe 'x' $nodeZipFile ('-o{0}' -f $outputRoot) '-y' | Write-WhiskeyVerbose

            # We use New-TimeSpan so we can mock it and in the mock wait for our simulated anti-virus process to lock a
            # file (i.e. so we can test that this wait logic works).
            $maxTime = New-TimeSpan -Seconds 10
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $exists = $false
            $lastError = $null
            Write-WhiskeyDebug "Renaming ""$($outputRoot)"" -> ""$($nodeDirectoryName)""."
            do
            {
                Rename-Item -Path $outputRoot -NewName $nodeDirectoryName -ErrorAction SilentlyContinue
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
                       """$($outputDirectoryName)"" to ""$($nodeDirectoryName)"" failed: $($lastError)"
                Write-WhiskeyError -Message $msg
            }

        }
        else
        {
            if( -not (Test-Path -Path $nodeRoot -PathType Container) )
            {
                New-Item -Path $nodeRoot -ItemType 'Directory' -Force | Out-Null
            }

            Write-WhiskeyVerbose -Message ('tar -xJf "{0}" -C "{1}" --strip-components=1' -f $nodeZipFile,$nodeRoot)
            tar -xJf $nodeZipFile -C $nodeRoot '--strip-components=1' | Write-WhiskeyVerbose
            if( $LASTEXITCODE )
            {
                Write-WhiskeyError -Message ('Failed to extract Node.js {0} package "{1}" to "{2}".' -f $nodeVersionToInstall.version,$nodeZipFile,$nodeRoot)
                return
            }
        }

        $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRoot -ErrorAction Stop
    }

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -NodeRootPath $nodeRoot -ErrorAction Stop
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
    $npmVersion = & $nodePath $npmPath '--version'
    if( $npmVersion -ne $npmVersionToInstall )
    {
        Write-WhiskeyVerbose ('Installing npm@{0}.' -f $npmVersionToInstall)
        # Bug in NPM 5 that won't delete these files in the node home directory.
        Get-ChildItem -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Include 'npm.cmd','npm','npx.cmd','npx' | Remove-Item
        & $nodePath $npmPath 'install' ('npm@{0}' -f $npmVersionToInstall) '-g' | Write-WhiskeyVerbose
        if( $LASTEXITCODE )
        {
            throw ('Failed to update to NPM {0}. Please see previous output for details.' -f $npmVersionToInstall)
        }
    }

    return $nodePath
}
