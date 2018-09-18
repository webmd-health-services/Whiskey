
function Install-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Installs PowerShell modules.
    
    .DESCRIPTION
    The `Install-WhiskeyPowerShellModule` function installs PowerShell modules into a "PSModules" directory in the directory of the current build (i.e. where the whiskey.yml file is located).

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
        # The path where the PSModules directory where the modules are installed is located. The default is the current directory.
        $Path = (Get-Location).ProviderPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Import-WhiskeyPowerShellModule -Name 'PackageManagement','PowerShellGet'

    $modulesRoot = Join-Path -Path $Path -ChildPath $powerShellModulesDirectoryName
    if( -not (Test-Path -Path $modulesRoot -PathType Container) )
    {
        New-Item -Path $modulesRoot -ItemType 'Directory' -ErrorAction Stop | Out-Null
    }

    $expectedPath = Join-Path -Path $modulesRoot -ChildPath $Name

    if( (Test-Path -Path $expectedPath -PathType Container) )
    {
        Resolve-Path -Path $expectedPath | Select-Object -ExpandProperty 'ProviderPath'
        return
    }

    $module = Resolve-WhiskeyPowerShellModule -Name $Name -Version $Version
    if( -not $module )
    {
        return
    }
                
    Save-Module -Name $Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot

    if( -not (Test-Path -Path $expectedPath -PathType Container) )
    {
        Write-Error -Message ('Failed to download {0} {1} from {2} ({3}). Either the {0} module does not exist, or it does but version {1} does not exist. Browse the PowerShell Gallery at https://www.powershellgallery.com/' -f $Name,$Version,$module.Repository,$module.RepositorySourceLocation)
    }

    return $expectedPath
}
