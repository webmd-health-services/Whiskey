
function Install-WhiskeyRequiredModule
{
    [CmdletBinding()]
    param(
        # The directory where package management modules should be installed.
        [Parameter(Mandatory)]
        [String] $PSModulesPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $DebugPreference = $VerbosePreference = 'Continue'

    function Wait
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, ValueFromPipeline)]
            [Object] $Job
        )

        process
        {
            if( (Get-Command -Name 'Receive-Job' -ParameterName 'AutoRemoveJob') )
            {
                $Job | Receive-Job -AutoRemoveJob -Wait
            }
            else
            {
                $Job | Wait-Job | Receive-Job
                $Job | Remove-Job
            }
        }
    }

    $requiredModules = @(
        [pscustomobject]@{
            Name = 'PowerShellGet';
            MinimumVersion = $script:psGetMinVersion;
            MaximumVersion = $script:psGetMaxVersion;
        },
        [pscustomobject]@{
            Name = 'PackageManagement';
            MinimumVersion = $script:pkgMgmtMinVersion;
            MaximumVersion = $script:pkgMgmtMaxVersion;
        }
    )

    Get-Module -Name ($requiredModules | Select-Object -ExpandProperty 'Name') -ListAvailable |
        Format-Table -Auto |
        Out-String |
        Write-WhiskeyDebug

    if( -not (Test-Path -Path $PSModulesPath) )
    {
        Write-WhiskeyDebug "Creating private modules directory ""$($PSModulesPath)""."
        New-Item -Path $PSModulesPath -ItemType 'Directory' | Out-Null
    }

    foreach( $requiredModule in $requiredModules )
    {
        $installedModules =
            Get-Module -Name $requiredModule.Name -ListAvailable |
            Where-Object 'Version' -GE $requiredModule.MinimumVersion |
            Where-Object 'Version' -LE $requiredModule.MaximumVersion
        if( $installedModules )
        {
            $msg = "Module $($requiredModule.Name) $($requiredModule.MinimumVersion) <= " +
                   "$($requiredModule.MaximumVersion) already installed."
            Write-WhiskeyDebug $msg
            $installedModules | Format-Table -Auto | Out-String | Write-WhiskeyDebug
            continue
        }

        Write-WhiskeyDebug "[Install   Begin   ]  [$($requiredModule.Name)]"
        Start-Job {
            $DebugPreference = $VerbosePreference = 'Continue'
            $name = $using:requiredModule.Name
            $version = $using:requiredModule.MaximumVersion
            $psModulesPath = $using:PSModulesPath

            $destinationPath = Join-Path -Path $psModulesPath -ChildPath $name
            # We're replacing a module that is already in place. Delete it before PowerShell auto-loads it.
            if( (Test-Path -Path $destinationPath) )
            {
                Write-Debug "Deleting existing $($name) module directory ""$($destinationPath)""."
                Remove-Item -Path $destinationPath -Recurse -Force
            }

            # Save to a temporary directory because `Save-Module` also installs dependencies, which we handle,
            # because otherwise we get into PackageManagement assembly loading hell.
            $savePath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
            if( -not (Test-Path -Path $savePath) )
            {
                Write-Debug "Creating temp directory ""$($savePath)"" for downloading $($name)."
                New-Item -Path $savePath -ItemType 'Directory' | Out-Null
            }

            try
            {
                Write-Debug "  PSModulePath"
                $env:PSModulePath -split ([IO.Path]::PathSeparator) | ForEach-Object { "    $($_)" } | Write-Debug
                Get-Module -ListAvailable -Name 'PowerShellGet' | Import-Module -ErrorAction SilentlyContinue
                Find-Module -Name $name -RequiredVersion $version |
                    Select-Object -First 1 |
                    ForEach-Object {
                        $msg = "Saving PowerShell module $($name) $($version) to " +
                                "$($psModulesPath | Resolve-Path -Relative)."
                        Write-Information $msg
                        $msg = "Downloading $($_.Name) $($_.Version) from $($_.RepositorySourceLocation) to " +
                                """$($savePath)""."
                        Write-Debug $msg
                        $_ | Save-Module -Path $savePath
                    }
                $dirsToCopy = Get-ChildItem -Path $savePath
                Write-Debug "Copying ""$($dirsToCopy.Name -join '", "' )"" modules to ""$($psModulesPath)""."
                # Remove any pre-existing modules in the destination. Those will be unsupported versions. When we
                # install PowerShellGet, its dependencies also get installed, always at the highest version. We
                # may not yet support that version, so must install a version we *do* support.
                $dirsToCopy |
                    ForEach-Object { Join-Path -Path $psModulesPath -ChildPath $_.Name } |
                    Where-Object { Test-Path -Path $_ } |
                    Remove-Item -Force -Recurse
                $dirsToCopy | Copy-Item -Destination $psModulesPath -Recurse -Force
            }
            finally
            {
                if( (Test-Path -Path $savePath) )
                {
                    Write-Debug "Deleting temp directory ""$($savePath)""."
                    Remove-Item -Path $savePath -Recurse -Force -ErrorAction Ignore
                }
            }
        } | Wait
        Write-WhiskeyDebug "[Install   Complete]  [$($requiredModule.Name)]"
    }

    # PowerShell will auto-import PackageManagement
    Import-Module -Name 'PowerShellGet' `
                  -MinimumVersion $script:psGetMinVersion `
                  -MaximumVersion $script:psGetMaxVersion `
                  -Global

    Write-WhiskeyDebug 'Imported PowerShellGet and PackageManagement modules.'
    Get-Module -Name 'PackageManagement','PowerShellGet' | Format-Table -Auto | Out-String | Write-WhiskeyDebug
    if( (Test-Path -Path 'env:APPVEYOR') )
    {
        Get-Module -Name ($requiredModules | Select-Object -ExpandProperty 'Name') -ListAvailable |
            Format-Table -Auto
    }
}