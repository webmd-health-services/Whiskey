
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

    function Invoke-InstallJob
    {
        param(
            [Parameter(ValueFromPipelineByPropertyName)]
            [String] $Name,

            [Parameter(ValueFromPipelineByPropertyName)]
            [Version] $MaximumVersion
        )

        Write-WhiskeyDebug "Installing $($Name) $($MaximumVersion) in a background job."
        Start-Job {
            $DebugPreference = $VerbosePreference = $using:DebugPreference
            $name = $using:Name
            $version = $using:MaximumVersion
            $psModulesPath = $using:PSModulesPath

            if( $name -eq 'PackageManagement' )
            {
                # If we previously installed PowerShellGet, it may have installed a too-new for Whiskey version of
                # PackageManagement. We deleted the too-new version of PackageManagement, which means the version of
                # PowerShellGet we installed won't import (its dependency is gone), so we try to import the newest
                # version of PowerShellGet that's installed in order to install PackageManagement
                $modules =
                    Get-Module -Name 'PowerShellGet' -ListAvailable | Sort-Object -Property 'Version'
                foreach( $module in $modules )
                {
                    $importError = $null
                    try
                    {
                        Write-Debug "Attempting import of $($module.Name) $($module.Version) from ""$($module.Path)""."
                        $module | Import-Module -ErrorAction SilentlyContinue -ErrorVariable 'importError'
                        if( (Get-Module -Name 'PowerShellGet') )
                        {
                            Write-Debug "Imported PowerShellGet $($module.Version)."
                            break
                        }
                        if( $importError )
                        {
                            Write-Debug "Errors importing $($module.Name) $($module.Version): $($importError)"
                            $Global:Error.RemoveAt(0)
                        }
                    }
                    catch
                    {
                        Write-Debug "Exception importing $($module.Name) $($module.Version): $($_)"
                    }
                }
            }

            Find-Module -Name $name -RequiredVersion $version |
                Select-Object -First 1 |
                ForEach-Object {
                    $msg = "Saving PowerShell module $($name) $($version) to " +
                            "$($psModulesPath | Resolve-Path -Relative)."
                    Write-Information $msg
                    $msg = "Downloading $($_.Name) $($_.Version) from $($_.RepositorySourceLocation) to " +
                            """$($psModulesPath)""."
                    Write-Debug $msg
                    $_ | Save-Module -Path $psModulesPath
                }
            } | Wait-InstallJob
            Write-WhiskeyDebug "$($Name) $($MaximumVersion) installation background job complete."
    }

    function Test-ModuleInstalled
    {
        param(
            [Parameter(ValueFromPipelineByPropertyName)]
            [String] $Name,

            [Parameter(ValueFromPipelineByPropertyName)]
            [Version] $MinimumVersion,

            [Parameter(ValueFromPipelineByPropertyName)]
            [Version] $MaximumVersion,

            [String] $Path,

            [switch] $PassThru
        )

        if( $Path )
        {
            $Name = Join-Path -Path $Path -ChildPath $Name
        }

        $module =
            Get-Module -Name $Name -ListAvailable |
            Where-Object 'Version' -GE $MinimumVersion |
            Where-Object 'Version' -LE $MaximumVersion

        if( $PassThru )
        {
            return $module
        }

        return $null -ne $module
    }

    function Wait-InstallJob
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

    $psGet = [pscustomobject]@{
        Name = 'PowerShellGet';
        MinimumVersion = $script:psGetMinVersion;
        MaximumVersion = $script:psGetMaxVersion;
    }

    $pkgMgmt =  [pscustomobject]@{
        Name = 'PackageManagement';
        MinimumVersion = $script:pkgMgmtMinVersion;
        MaximumVersion = $script:pkgMgmtMaxVersion;
    }

    $requiredModules = @( $psGet, $pkgMgmt )

    Get-Module -Name $requiredModules.Name -ListAvailable | Format-Table -Auto | Out-String | Write-WhiskeyDebug

    if( -not (Test-Path -Path $PSModulesPath) )
    {
        Write-WhiskeyDebug "Creating private modules directory ""$($PSModulesPath)""."
        New-Item -Path $PSModulesPath -ItemType 'Directory' | Out-Null
    }

    if( -not ($psGet | Test-ModuleInstalled) )
    {
        $psGet | Invoke-InstallJob
    }

    $psGetModule = $psGet | Test-ModuleInstalled -PassThru
    # Make sure Package Management minimum version matches PowerShellGet's minium version.
    $pkgMgmt.MinimumVersion =
        $psGetModule.RequiredModules |
        Where-Object 'Name' -EQ $pkgMgmt.Name |
        Select-Object -ExpandProperty 'Version'

    if( -not ($pkgMgmt | Test-ModuleInstalled) )
    {
        # PowerShellGet depends on PackageManagement, so Save-Module/Install-Module will install the latest version of
        # PackageManagement if a version PowerShellGet can use isn't installed. Whiskey may not support the latest version.
        # So, if Save-Module installed an incompatible version of PackageManagement, we need to remove it.
        $tooNewPkgMgmtPath = Join-Path -Path $PSModulesPath -ChildPath $pkgMgmt.Name
        Get-Module -Name $tooNewPkgMgmtPath -ListAvailable -ErrorAction Ignore |
            Where-Object 'Version' -GT $pkgMgmt.MaximumVersion |
            ForEach-Object {
                $pathToDelete = $_ | Split-Path -Parent
                $msg = "Deleting unsupported $($_.Name) $($_.Version) from " +
                       """$($pathToDelete | Resolve-Path -Relative)""."
                Write-Debug $msg
                Remove-Item -Path $pathToDelete -Recurse -Force
            }

        $pkgMgmt | Invoke-InstallJob
    }

    # PowerShell will auto-import PackageManagement because PowerShellGet depends on it.
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