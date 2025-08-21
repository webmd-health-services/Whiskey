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
        $pkgPath =
            Save-NodeJsPackage -Version $versionToInstall -OutputDirectoryPath $TaskContext.OutputDirectory -Cpu $Cpu
        if (-not $pkgPath)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message "Failed to download Node.js ${versionToInstall}."
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
            Invoke-WhiskeyNpmCommand -NpmPath $npmPath -ArgumentList 'install',"npm@${NpmVersion}",'-g'
        }
    }
}