
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

        # Don't import the module.
        [switch]$SkipImport
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $module = $null
    if( -not $Version )
    {
        $module = Resolve-WhiskeyPowerShellModule -Name $Name -BuildRoot $BuildRoot
        if( -not $module )
        {
            return
        }
        $Version = $module.Version
    }

    $modulesRoot = Join-Path -Path $BuildRoot -ChildPath $powerShellModulesDirectoryName
    $moduleRoot = Join-Path -Path $modulesRoot -ChildPath $Name
    $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath ('{0}\{1}.psd1' -f $Version,$Name)

    $manifest = $null
    $manifestOk = $false
    try
    {
        $manifest =
            Get-Item -Path $moduleManifestPath -ErrorAction Ignore |
            Test-ModuleManifest -ErrorAction Ignore |
            Sort-Object -Property 'Version' -Descending |
            Select-Object -First 1
        $manifestOk = $true
    }
    catch
    {
        $Global:Error.RemoveAt(0)
    }

    if( $manifestOk -and $manifest )
    {
        $manifest
    }
    else
    {
        $module = $null
        if( -not $manifest )
        {
            $module = Resolve-WhiskeyPowerShellModule -Name $Name -Version $Version -BuildRoot $BuildRoot
            if( -not $module )
            {
                return
            }
        }

        Write-WhiskeyVerbose -Message ('Saving PowerShell module {0} {1} to "{2}" from repository {3}.' -f $Name,$module.Version,$modulesRoot,$module.Repository)
        Save-Module -Name $Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot

        $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath ('{0}\{1}.psd1' -f $module.Version,$Name)
        $manifest = Test-ModuleManifest -Path $moduleManifestPath -ErrorAction Ignore
        if( -not $manifest )
        {
            Write-WhiskeyError -Message ('Failed to download {0} {1} from {2} ({3}). Either the {0} module does not exist, or it does but version {1} does not exist.' -f $Name,$Version,$module.Repository,$module.RepositorySourceLocation)
            return
        }
        $manifest
    }

    if( -not $SkipImport )
    {
        Import-WhiskeyPowerShellModule -Name $Name -BuildRoot $BuildRoot
    }
}
