
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
            Name = 'PackageManagement';
            MinimumVersion = $script:pkgMgmtMinVersion;
            MaximumVersion = $script:pkgMgmtMaxVersion;
            ClearPSModulePath = $false;
        },
        [pscustomobject]@{
            Name = 'PowerShellGet';
            MinimumVersion = $script:psGetMinVersion;
            MaximumVersion = $script:psGetMaxVersion;
            ClearPSModulePath = $true;
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

    Write-WhiskeyDebug "[Install   Begin   ]  $(Get-Date)"
    & {
        foreach( $requiredModule in $requiredModules )
        {
            $installedModules =
                Get-Module -Name $requiredModule.Name -ListAvailable |
                Where-Object 'Version' -GE $requiredModule.MinimumVersion |
                Where-Object 'Version' -LE $requiredModule.MaximumVersion
            if( $installedModules )
            {
                continue
            }

            Start-Job {
                $DebugPreference = $VerbosePreference = 'Continue'
                $name = $using:requiredModule.Name
                $version = $using:requiredModule.MaximumVersion
                $psModulesPath = $using:PSModulesPath

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
                    Write-Debug "[Install           ]  [$($name)]  $(Get-Date)"
                    Write-Debug "  PSModulePath"
                    $env:PSModulePath -split ([IO.Path]::PathSeparator) | ForEach-Object { "    $($_)" } | Write-Debug
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
                    $sourcePath = Join-Path -Path $savePath -ChildPath $name
                    Write-Debug "Copying $($sourcePath) to ""$($psModulesPath)""."
                    Copy-Item -Path $sourcePath -Destination $psModulesPath -Recurse -Force
                }
                finally
                {
                    if( (Test-Path -Path $savePath) )
                    {
                        Write-Debug "Deleting temp directory ""$($savePath)""."
                        Remove-Item -Path $savePath -Recurse -Force -ErrorAction Ignore
                    }
                }
            } | Write-Output
        }
    } | Wait

    Write-WhiskeyDebug "[Install   Complete]  $(Get-Date)"

    foreach( $requiredModule in $requiredModules )
    {
        $msg = "[Import]  $($requiredModule.Name)  $($requiredModule.MinimumVersion) <= " +
               "$($requiredModule.MaximumVersion)"
        Write-WhiskeyDebug $msg
        Import-Module -Name $requiredModule.Name `
                      -MinimumVersion $requiredModule.MinimumVersion `
                      -MaximumVersion $requiredModule.MaximumVersion `
                      -Global
    }

    if( (Test-Path -Path 'env:APPVEYOR') )
    {
        Get-Module -Name ($requiredModules | Select-Object -ExpandProperty 'Name') -ListAvailable |
            Format-Table -Auto
    }
}