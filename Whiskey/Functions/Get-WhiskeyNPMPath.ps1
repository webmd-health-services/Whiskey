
function Get-WhiskeyNpmPath
{

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $NodePath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nodeRoot = $NodePath | Split-Path
    $npmGlobalPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js'

    if( -not (Test-Path -Path $npmGlobalPath -PathType Leaf) )
    {
        throw ('NPM not installed in {0}. Make sure your task has the `[Whiskey.RequiresTool("Node", "NodePath")]` attribute defined so that Node gets installed. It should come before any `RequiresTool` attributes for Node modules.' -f $nodeRoot)
    }

    return $npmGlobalPath
}