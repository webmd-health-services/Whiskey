
function Uninstall-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Cleans downloaded PowerShell modules.
    
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
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the module to install.
        $Name,

        [string]
        $Version = '*.*.*',

        # The path where the PSModules directory where the modules are installed is located. The default is the current directory.
        $Path = (Get-Location).ProviderPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Get-Module -Name $Name | Remove-Module -Force

    $modulesRoot = Join-Path -Path $Path -ChildPath $powerShellModulesDirectoryName
    # Remove modules saved by either PowerShell4 or PowerShell5
    $moduleRoots = @( ('{0}\{1}' -f $Name, $Version), ('{0}' -f $Name)  )
    foreach ($item in $moduleRoots)
    {
        $removeModule = (Join-Path -Path $modulesRoot -ChildPath $item )
        if( Test-Path -Path $removeModule -PathType Container )
        {
            Remove-Item $removeModule -Recurse -Force
            return
        }
    }
}
