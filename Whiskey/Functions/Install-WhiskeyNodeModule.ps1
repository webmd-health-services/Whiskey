
function Install-WhiskeyNodeModule
{
    <#
    .SYNOPSIS
    Installs Node.js modules

    .DESCRIPTION
    The `Install-WhiskeyNodeModule` function installs Node.js modules to the `node_modules` directory located in the current working directory. The path to the module's directory is returned.

    Failing to install a module does not cause a bulid to fail. If you want a build to fail if the module fails to install, you must pass `-ErrorAction Stop`.

    .EXAMPLE
    Install-WhiskeyNodeModule -Name 'rimraf' -Version '^2.0.0' -NodePath $TaskParameter['NodePath']

    This example will install the Node module `rimraf` at the latest `2.x.x` version in the `node_modules` directory located in the current directory.

    .EXAMPLE
    Install-WhiskeyNodeModule -Name 'rimraf' -Version '^2.0.0' -NodePath $TaskParameter['NodePath -ErrorAction Stop

    Demonstrates how to fail a build if installing the module fails by setting the `ErrorAction` parameter to `Stop`.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The name of the module to install.
        [String]$Name,

        # The version of the module to install.
        [String]$Version,

        # Node modules are being installed on a developer computer.
        [switch]$ForDeveloper,

        [Parameter(Mandatory)]
        # The path to the build directory.
        [String]$BuildRootPath,

        # Whether or not to install the module globally.
        [switch]$Global,

        # Are we running in clean mode?
        [switch]$InCleanMode
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $npmArgument = & {
                        if( $Version )
                        {
                            ('{0}@{1}' -f $Name,$Version)
                        }
                        else
                        {
                            $Name
                        }
                        if( $Global )
                        {
                            '-g'
                        }
                    }

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $BuildRootPath -Global:$Global -ErrorAction Ignore
    if( $modulePath )
    {
        return $modulePath
    }
    elseif( $InCleanMode )
    {
        return
    }

    Invoke-WhiskeyNpmCommand -Name 'install' -ArgumentList $npmArgument -BuildRootPath $BuildRootPath -ForDeveloper:$ForDeveloper |
        Write-WhiskeyVerbose
    if( $LASTEXITCODE )
    {
        return
    }

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $BuildRootPath -Global:$Global -ErrorAction Ignore
    if( -not $modulePath )
    {
        Write-WhiskeyError -Message ('NPM executed successfully when attempting to install "{0}" but the module was not found anywhere in the build directory "{1}"' -f ($npmArgument -join ' '),$BuildRootPath)
        return
    }

    return $modulePath
}
