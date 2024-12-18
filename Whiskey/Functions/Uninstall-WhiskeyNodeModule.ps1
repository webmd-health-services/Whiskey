
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
        [Parameter(Mandatory)]
        # The name of the module to uninstall.
        [String]$Name,

        [Parameter(Mandatory)]
        # The path to the build directory.
        [String]$BuildRootPath,

        # Node modules are being uninstalled on a developer computer.
        [switch]$ForDeveloper,

        # Remove the module manually if NPM fails to uninstall it
        [switch]$Force,

        # Uninstall the module from the global cache.
        [switch]$Global
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
            Write-WhiskeyError -Message ('Failed to remove Node module "{0}" from "{1}". See previous errors for more details.' -f $Name,$modulePath)
            return
        }
    }

    if( $modulePath -and (Test-Path -Path $modulePath -PathType Container) )
    {
        Write-WhiskeyError -Message ('Failed to remove Node module "{0}" from "{1}" using both "npm prune" and manual removal. See previous errors for more details.' -f $Name,$modulePath)
        return
    }
}
