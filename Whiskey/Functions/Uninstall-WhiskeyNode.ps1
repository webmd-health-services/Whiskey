
function Uninstall-WhiskeyNode
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The directory where node is installed and from which it should be removed.
        [String]$InstallRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $dirToRemove = Join-Path -Path $InstallRoot -ChildPath '.node'
    Remove-WhiskeyFileSystemItem -Path $dirToRemove
}
