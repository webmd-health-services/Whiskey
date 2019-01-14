
function Uninstall-WhiskeyNodeModule
{
    <#
    .SYNOPSIS
    Uninstalls Node.js modules.
    
    .DESCRIPTION
    The `Uninstall-WhiskeyNodeModule` function will uninstall Node.js modules from the `node_modules` directory in the current working directory. It uses the `npm uninstall` command to remove the module.
    
    If the `npm uninstall` command fails to uninstall the module and the `Force` parameter was not used, then the function will write an error and return. If the `Force` parameter is used then the function will attempt to manually remove the module if `npm uninstall` fails.
    
    .EXAMPLE
    Uninstall-WhiskeyNodeModule -Name 'rimraf' -NodePath $TaskParameter['NodePath']
    
    Removes the node module 'rimraf' from the `node_modules` directory in the current directory.

    .EXAMPLE
    Uninstall-WhiskeyNodeModule -Name 'rimraf' -NodePath $TaskParameter['NodePath'] -Force
    
    Removes the node module 'rimraf' from `node_modules` directory in the current directory. Because the `Force` switch is used, if `npm uninstall` fails, will attemp to use PowerShell to remove the module.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the module to uninstall.
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        # The path to the build root directory.
        $BuildRootPath,

        [switch]
        # Node modules are being uninstalled on a developer computer.
        $ForDeveloper,

        [switch]
        # Remove the module manually if NPM fails to uninstall it
        $Force,

        [Switch]
        # Uninstall the module from the global cache.
        $Global
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $argumentList = & {
                        $Name
                        if( $Global )
                        {
                            '-g'
                        }
                    }

    Invoke-WhiskeyNpmCommand -Name 'uninstall' `
                             -BuildRootPath $BuildRootPath `
                             -ArgumentList $argumentList `
                             -ForDeveloper:$ForDeveloper
    
    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $BuildRootPath -Global:$Global -ErrorAction Ignore

    if( $modulePath )
    {
        if( $Force )
        {
            Remove-WhiskeyFileSystemItem -Path $modulePath
        }
        else
        {
            Write-Error -Message ('Failed to remove Node module "{0}" from "{1}". See previous errors for more details.' -f $Name,$modulePath)
            return
        }
    }

    if( $modulePath -and (Test-Path -Path $modulePath -PathType Container) )
    {
        Write-Error -Message ('Failed to remove Node module "{0}" from "{1}" using both "npm prune" and manual removal. See previous errors for more details.' -f $Name,$modulePath)
        return
    }
}
