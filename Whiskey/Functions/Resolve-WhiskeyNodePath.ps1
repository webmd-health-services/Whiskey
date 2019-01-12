
function Resolve-WhiskeyNodePath
{
    <#
    .SYNOPSIS
    Gets the path to the Node executable.

    .DESCRIPTION
    The `Resolve-WhiskeyNodePath` resolves the path to the Node executable in a cross-platform manner. The path/name of the Node executable is different on different operating systems. Pass the path to the root directory where Node is installed to the `NodeRootPath` parameter.

    If you want the path to the local version of Node that Whiskey installs for tasks that need it, pass the build root path to the `BuildRootPath` parameter.

    Returns the full path to the Node executable. If one isn't found, writes an error and returns nothing.

    .EXAMPLE
    Resolve-WhiskeyNodePath -NodeRootPath $pathToNodeInstallRoot

    Demonstrates how to get the path to the Node executable when the path to the root Node directory is in the `$pathToInstallRoot` variable.

    .EXAMPLE
    Resolve-WhiskeyNodePath -BuildRootPath $TaskContext.BuildRoot

    Demonstrates how to get the path to the Node executable in the directory where Whiskey installs it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='FromBuildRoot')]
        [string]
        # The path to the build root. This will return the path to Node where Whiskey installs a local copy.
        $BuildRootPath,

        [Parameter(Mandatory,ParameterSetName='FromNodeRoot')]
        [string]
        # The path to the root of an Node package, as downloaded and expanded from the Node.js download page.
        $NodeRootPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $PSCmdlet.ParameterSetName -eq 'FromBuildRoot' )
    {
        return (Resolve-WhiskeyNodePath -NodeRootPath (Join-Path -Path $BuildRootPath -ChildPath '.node'))
    }

    $nodePath = & {
                        Join-Path -Path $NodeRootPath -ChildPath 'bin/node'
                        Join-Path -Path $NodeRootPath -ChildPath 'node.exe'
                } |
                ForEach-Object {
                    Write-Debug -Message ('Looking for Node executable at "{0}".' -f $_)
                    $_
                } |
                Where-Object { Test-Path -Path $_ -PathType Leaf } |
                Select-Object -First 1 |
                Resolve-Path |
                Select-Object -ExpandProperty 'ProviderPath'

    if( -not $nodePath )
    {
        Write-Error -Message ('Node executable doesn''t exist in "{0}".' -f $NodeRootPath) -ErrorAction $ErrorActionPreference
        return
    }

    Write-Debug -Message ('Found Node executable at "{0}".' -f $nodePath)
    return $nodePath
}