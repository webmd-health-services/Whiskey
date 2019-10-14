
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
        # The name of the module to install.
        [string]$Name,

        # The version of the module to install.
        [string]$Version,

        [Parameter(Mandatory)]
        # Modules are saved into a PSModules directory. This is the directory where PSModules directory should created, *not* the path to the PSModules directory itself, i.e. this is the path to the "PSModules" directory's parent directory.
        [string]$BuildRoot,

        # Don't import the module.
        [Switch]$SkipImport
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
    $modulePath = Join-Path -Path $moduleRoot -ChildPath ('{0}\{1}.psd1' -f $Version,$Name)

    if( (Test-Path -Path $modulePath -PathType Leaf) )
    {
        $moduleRoot | Resolve-Path | Select-Object -ExpandProperty 'ProviderPath'
    }
    else
    {
        if( -not $module )
        {
            $module = Resolve-WhiskeyPowerShellModule -Name $Name -Version $Version -BuildRoot $BuildRoot
            if( -not $module )
            {
                return
            }
        }

        Write-Verbose -Message ('Saving PowerShell module {0} {1} to "{2}" from repository {3}.' -f $Name,$module.Version,$modulesRoot,$module.Repository)
        Save-Module -Name $Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot

        $modulePath = Join-Path -Path $moduleRoot -ChildPath ('{0}\{1}.psd1' -f $module.Version,$Name)
        if( -not (Test-Path -Path $modulePath -PathType Leaf) )
        {
            Write-Error -Message ('Failed to download {0} {1} from {2} ({3}). Either the {0} module does not exist, or it does but version {1} does not exist.' -f $Name,$Version,$module.Repository,$module.RepositorySourceLocation)
        }
        $moduleRoot | Resolve-Path | Select-Object -ExpandProperty 'ProviderPath'
    }

    if( -not $SkipImport )
    {
        Import-WhiskeyPowerShellModule -Name $Name -BuildRoot $BuildRoot
    }
}
