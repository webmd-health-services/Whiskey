
function Uninstall-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Removes downloaded PowerShell modules.

    .DESCRIPTION
    The `Uninstall-WhiskeyPowerShellModule` function deletes downloaded PowerShell modules from Whiskey's local "PSModules" directory.

    .EXAMPLE
    Uninstall-WhiskeyPowerShellModule -Name 'Pester'

    This example will uninstall the PowerShell module `Pester` from Whiskey's local `PSModules` directory.

    .EXAMPLE
    Uninstall-WhiskeyPowerShellModule -Name 'Pester' -ErrorAction Stop

    Demonstrates how to fail a build if uninstalling the module fails by setting the `ErrorAction` parameter to `Stop`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The name of the module to uninstall.
        [string]$Name,

        [string]$Version = '*.*.*',

        [Parameter(Mandatory)]
        # Modules are saved into a PSModules directory. This is the path where the PSModules directory was created and should be the same path passed to `Install-WhiskeyPowerShellModule`.
        [string]$BuildRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Get-Module -Name $Name | Remove-Module -Force

    $modulesRoot = Join-Path -Path $BuildRoot -ChildPath $powerShellModulesDirectoryName
    # Remove modules saved by either PowerShell4 or PowerShell5
    $moduleRoots = @( ('{0}\{1}' -f $Name, $Version) )
    foreach ($item in $moduleRoots)
    {
        $removeModule = (Join-Path -Path $modulesRoot -ChildPath $item )
        if( Test-Path -Path $removeModule -PathType Container )
        {
            Remove-Item -Path $removeModule -Recurse -Force
            break
        }
    }

    if( (Test-Path -Path $modulesRoot -PathType Container) )
    {
        $psmodulesDirEmpty = $null -eq (Get-ChildItem -Path $modulesRoot -File -Recurse)
        if( $psmodulesDirEmpty )
        {
            Remove-Item -Path $modulesRoot -Recurse -Force
        }
    }
}
