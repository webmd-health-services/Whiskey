
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
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the module to install.
        $Name,

        [string]
        # The version of the module to install.
        $Version,

        [string]
        # Modules are saved into a PSModules directory. The "Path" parameter is the path where this PSModules directory should be, *not* the path to the PSModules directory itself, i.e. this is the path to the "PSModules" directory's parent directory.
        $Path = (Get-Location).ProviderPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $modulesRoot = Join-Path -Path $Path -ChildPath $powerShellModulesDirectoryName
    if( -not (Test-Path -Path $modulesRoot -PathType Container) )
    {
        New-Item -Path $modulesRoot -ItemType 'Directory' -ErrorAction Stop | Out-Null
    }

    $packageManagementPackages = @{
                                    'PackageManagement' = '1.4.5';
                                    'PowerShellGet' = '2.2.1'
                                 }
    $modulesToInstall = New-Object 'Collections.ArrayList' 
    foreach( $packageName in $packageManagementPackages.Keys )
    {
        $packageVersion = $packageManagementPackages[$packageName]
        $moduleRootPath = Join-Path -Path $modulesRoot -ChildPath ('{0}\{1}' -f $packageName,$packageVersion)
        if( -not (Test-Path -Path $moduleRootPath -PathType Container) )
        {
            Write-WhiskeyTiming -Message ('Module "{0}" version {1} does not exist at {2}.' -f $packageName,$packageVersion,$moduleRootPath)
            $module = [pscustomobject]@{ 'Name' = $packageName ; 'Version' = $packageVersion }
            [void]$modulesToInstall.Add($module)
        }
    }

    if( $modulesToInstall.Count )
    {
        Write-WhiskeyTiming -Message ('Installing package management modules to {0}.  BEGIN' -f $modulesRoot)
        # Install Package Management modules in the background so we can load the new versions. These modules use 
        # assemblies so once you load an old version, you have to re-launch your process to load a newer version.
        Start-Job -ScriptBlock {
            $modulesToInstall = $using:modulesToInstall
            $modulesRoot = $using:modulesRoot

            Get-PackageProvider -Name 'NuGet' -ForceBootstrap | Out-Null
            foreach( $moduleInfo in $modulesToInstall )
            {
                $module = Find-Module -Name $moduleInfo.Name -RequiredVersion $moduleInfo.Version
                if( -not $module )
                {
                    continue
                }

                Write-Verbose -Message ('Saving PowerShell module {0} {1} to "{2}" from repository {3}.' -f $module.Name,$module.Version,$modulesRoot,$module.Repository)
                Save-Module -Name $module.Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot
            }
        } | Receive-Job -Wait -AutoRemoveJob | Out-Null
        Write-WhiskeyTiming -Message ('                                               END')
    }

    Import-WhiskeyPowerShellModule -Name 'PackageManagement','PowerShellGet'

    Get-PackageProvider -Name 'NuGet' -ForceBootstrap | Out-Null

    $expectedPath = Join-Path -Path $modulesRoot -ChildPath $Name

    if( (Test-Path -Path $expectedPath -PathType Container) -and (Get-ChildItem -Path $expectedPath -File -Filter ('{0}.psd1' -f $Name) -Recurse))
    {
        Resolve-Path -Path $expectedPath | Select-Object -ExpandProperty 'ProviderPath'
        return
    }

    $module = Resolve-WhiskeyPowerShellModule -Name $Name -Version $Version
    if( -not $module )
    {
        return
    }

    Write-Verbose -Message ('Saving PowerShell module {0} {1} to "{2}" from repository {3}.' -f $Name,$module.Version,$modulesRoot,$module.Repository)
    Save-Module -Name $Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot

    if( -not (Test-Path -Path $expectedPath -PathType Container) )
    {
        Write-Error -Message ('Failed to download {0} {1} from {2} ({3}). Either the {0} module does not exist, or it does but version {1} does not exist. Browse the PowerShell Gallery at https://www.powershellgallery.com/' -f $Name,$Version,$module.Repository,$module.RepositorySourceLocation)
    }

    return $expectedPath
}
