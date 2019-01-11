
function Resolve-WhiskeyNodeModulePath
{
    <#
    .SYNOPSIS
    Gets the path to Node module's directory.

    .DESCRIPTION
    The `Resolve-WhiskeyNodeModulePath` resolves the path to a Node modules's directory. Pass the name of the module to the `Name` parameter. Pass the path to the build root to the `BuildRootPath` (this is usually where the package.json file is). The function will return the path to the Node module's directory in the local "node_modules" directory. Whiskey installs a private copy of Node for you into a ".node" directory in the build root. If you want to get the path to a global module from this private location, use the `-Global` switch.
    
    To get the Node module's directory from an arbitrary directory where Node is installed, pass the install directory to the `NodeRootPath` directory. This function handles the different locations of the "node_modules" directory across/between operating systems.

    If the Node module isn't installed, you'll get an error and nothing will be returned.

    .EXAMPLE
    Resolve-WhiskeyNodeModulePath -Name 'npm' -NodeRootPath $pathToNodeInstallRoot

    Demonstrates how to get the path to the `npm' module's directory from the "node_modules" directory from a directory where Node is installed, given by the `$pathToInstallRoot` variable.

    .EXAMPLE
    Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $TaskContext.BuildRoot

    Demonstrates how to get the path to a Node module's directory where Node installs a local copy. In this case, `Join-Path -Path $TaskContext.BuildRoot -ChildPath 'node_modules\npm'` would be returned (if it exists).

    .EXAMPLE
    Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $TaskContext.BuildRoot -Global

    Demonstrates how to get the path to a globally installed Node module's directory. Whiskey installs a private copy of Node into a ".node" directory in the build root, so this example would return a path to the module in that directory (if it exists). That path can be different between operating systems.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        # The name of the Node module whose path to get.
        $Name,

        [Parameter(Mandatory,ParameterSetName='FromBuildRoot')]
        [string]
        # The path to the build root. This will return the path to Node modules's directory from the "node_modules" directory in the build root. If you want the path to a global node module, installed in the local Node directory Whiskey installs in the repository, use the `-Global` switch.
        $BuildRootPath,

        [Parameter(ParameterSetName='FromBuildRoot')]
        [Switch]
        # Get the path to a Node module in the global "node_modules" directory. The default is to get the path to the copy in the local node_modules directory.
        $Global,

        [Parameter(Mandatory,ParameterSetName='FromNodeRoot')]
        [string]
        # The path to the root of a Node package, as downloaded and expanded from the Node.js project.
        $NodeRootPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $PSCmdlet.ParameterSetName -eq 'FromBuildRoot' )
    {
        if( $Global )
        {
            return (Resolve-WhiskeyNodeModulePath -NodeRootPath (Join-Path -Path $BuildRootPath -ChildPath '.node') -Name $Name)
        }

        return (Resolve-WhiskeyNodeModulePath -NodeRootPath $BuildRootPath -Name $Name)
    }

    $nodeModulePath = & {
                            Join-Path -Path $NodeRootPath -ChildPath 'lib/node_modules'
                            Join-Path -Path $NodeRootPath -ChildPath 'node_modules'
                        } |
                        ForEach-Object { Join-Path -Path $_ -ChildPath $Name } |
                        Where-Object { Test-Path -Path $_ -PathType Container } |
                        Select-Object -First 1 |
                        Resolve-Path |
                        Select-Object -ExpandProperty 'ProviderPath'

    if( -not $nodeModulePath )
    {
        Write-Error -Message ('Node module "{0}" directory doesn''t exist in "{1}".' -f $Name,$NodeRootPath) -ErrorAction $ErrorActionPreference
        return
    }

    return $nodeModulePath
}