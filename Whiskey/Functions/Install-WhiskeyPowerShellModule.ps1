
function Install-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Installs a PowerShell module.

    .DESCRIPTION
    The `Install-WhiskeyPowerShellModule` function installs a PowerShell module into a "PSModules" directory in the current working directory. It returns the path to the module.

    .EXAMPLE
    Install-WhiskeyPowerShellModule -Name 'Pester' -Version '4.3.0'

    This example will install the PowerShell module `Pester` at version `4.3.0` version in the `PSModules` directory.

    .EXAMPLE
    Install-WhiskeyPowerShellModule -Name 'Pester' -Version '4.*'

    Demonstrates that you can use wildcards to choose the latest minor version of a module.

    .EXAMPLE
    Install-WhiskeyPowerShellModule -Name 'Pester' -Version '4.3.0' -ErrorAction Stop

    Demonstrates how to fail a build if installing the module fails by setting the `ErrorAction` parameter to `Stop`.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The name of the module to install.
        [String]$Name,

        # The version of the module to install.
        [String]$Version,

        [Parameter(Mandatory)]
        # Modules are saved into a PSModules directory. This is the directory where PSModules directory should created, *not* the path to the PSModules directory itself, i.e. this is the path to the "PSModules" directory's parent directory.
        [String]$BuildRoot,

        # The path to a custom directory where you want the module installed. The default is `PSModules` in the build root.
        [String]$Path,

        # Don't import the module.
        [switch]$SkipImport,

        # Allow prerelease versions.
        [switch]$AllowPrerelease
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyDebug "\Install-WhiskeyPowerShellModule\" -Indent

    try
    {
        function Find-PSModule
        {
            $findParameters = @{
                'Name' = $Name;
                'BuildRoot' = $BuildRoot;
                'AllowPrerelease' = $AllowPrerelease;
                'Version' = $Version;
            }

            return Find-WhiskeyPowerShellModule @findParameters
        }

        Write-WhiskeyDebug ($PSBoundParameters | Format-Table | Out-String)
        if( $Path )
        {
            $Path = $Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if( -not [IO.Path]::IsPathRooted($Path) )
            {
                $Path = Join-Path -Path $BuildRoot -ChildPath $Path
                $Path = [IO.Path]::GetFullPath($Path)
            }
            if( -not (Test-Path -Path $Path) )
            {
                New-Item -Path $Path -ItemType 'Directory' | Out-Null
            }

            # Whiskey's PowerShell functions assume all modules are installed in a path in PSModulePath environment variable
            # so make sure the user's path is in that path.
            Register-WhiskeyPSModulePath -Path $Path
            $installRoot = $Path
        }
        else
        {
            $installRoot = Get-WhiskeyPSModulePath -PSModulesRoot $BuildRoot -Create
        }
        Write-WhiskeyDebug "Module $($Name) $($Version) will be installed to ""$($installRoot)""."

        if( -not $Version )
        {
            Write-WhiskeyDebug "Searching for latest $($Name) module version."
            # We need to know the latest version of the module so we can see if it is already installed.
            $latestModule = Find-PSModule
            if( -not $latestModule )
            {
                Write-WhiskeyDebug "Module $($Name) not found in any repository."
                return
            }
            Write-WhiskeyDebug ($latestModule | Format-List | Out-String)
            $Version = $latestModule.Version
        }

        try
        {
            $installedModule = Get-WhiskeyPSModule -PSModulesRoot $BuildRoot -Name $Name -Version $Version

            if( $installedModule )
            {
                Write-WhiskeyDebug "Module $($Name) $($Version) found:$([Environment]::NewLine)$($installedModule | Format-List)"
                $installedInPSModulePath = -not $Path
                $installedInCustomPath = $Path -and `
                                        ($installedModule.Path | Split-Path | Split-Path | Split-Path) -eq $Path
                if( $installedInPSModulePath -or $installedInCustomPath )
                {
                    if( -not $SkipImport )
                    {
                        Import-WhiskeyPowerShellModule -Name $Name -Version $installedModule.Version -PSModulesRoot $BuildRoot
                    }

                    # Already installed or installed where the user wants it.
                    return $installedModule
                }
            }

            Write-WhiskeyDebug "Module $($Name) $($Version) not installed."
            # Find what module *should* be installed.
            $moduleToInstall = Find-PSModule
            if( -not $moduleToInstall )
            {
                Write-WhiskeyDebug "Module $($Name) $($Version) not found in any repository."
                return
            }

            Write-WhiskeyDebug "Module $($Name) $($Version) found: $($moduleToInstall | Format-List | Out-String)."
            # Now we know where the module is going to be saved, let's make sure the destination doesn't exist.
            $moduleRoot = Join-Path -Path $installRoot -ChildPath $moduleToInstall.Name
            $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $moduleToInstall.Version
            if( (Test-Path -Path $moduleRoot) )
            {
                Write-WhiskeyDebug "Removing module $($Name) $($Version) destination directory ""$($moduleRoot)""."
                Remove-Item -Path $moduleRoot -Recurse -Force
                if( (Test-Path -Path $moduleRoot) )
                {
                    $msg = "Unable to install PowerShell module $($moduleToInstall.Name) $($moduleToInstall.Version) to " +
                        """$($installRoot | Resolve-Path -Relative)"": the destination path " +
                        """$($moduleRoot | Resolve-Path -Relative)"" exists and deleting it failed. Make sure files " +
                        'under the destination directory aren''t in use.'
                    Write-WhiskeyError -Message $msg
                    return
                }
            }

            $msg = "Saving PowerShell module ""$($moduleToInstall.Name)"" $($moduleToInstall.Version) from repository " + 
                """$($moduleToInstall.Repository)"" to ""$($installRoot)""."
            Write-WhiskeyVerbose -Message $msg
            $globalProgressPref = $Global:ProgressPreference
            # Ignore doesn't work in Windows PowerShell.
            $Global:ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
            $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Save-Module' -AllowPrerelease:$AllowPrerelease
            try
            {
                Save-Module -Name $moduleToInstall.Name `
                            -RequiredVersion $moduleToInstall.Version `
                            -Repository $moduleToInstall.Repository `
                            -Path $installRoot `
                            @allowPrereleaseArg
            }
            finally
            {
                $Global:ProgressPreference = $globalProgressPref
            }
            $installedModule = Get-WhiskeyPSModule -PSModulesRoot $BuildRoot `
                                                -Name $moduleToInstall.Name `
                                                -Version $moduleToInstall.Version

            if( -not $installedModule )
            {
                $msg = "Failed to download PowerShell module $($moduleToInstall.Name) $($moduleToInstall.Version) from " +
                    "repository $($moduleToInstall.Repository) to ""$($installRoot | Resolve-Path -Relative)"": the " +
                    'module doesn''t exist after running PowerShell''s "Save-Module" command.'
                Write-WhiskeyError -Message $msg
                return
            }

            $installedModule | Write-Output

            if( -not $SkipImport )
            {
                Import-WhiskeyPowerShellModule -Name $Name -Version $installedModule.Version -PSModulesRoot $BuildRoot
            }
        }
        finally
        {
            if( $Path )
            {
                # Remove the user's path from the PSModulePath environment variable.
                Unregister-WhiskeyPSModulePath -Path $Path
            }
        }
    }
    finally
    {
        Write-WhiskeyDebug "/Install-WhiskeyPowerShellModule/" -Outdent
    }
}
