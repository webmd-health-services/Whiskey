
function Copy-WhiskeyFile
{
    [Whiskey.Task('CopyFile')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory',AllowNonexistent,Create)]
        [String[]]$DestinationDirectory
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState


    if( -not $DestinationDirectory )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property "DestinationDirectory" didn''t resolve to any existing paths.'
        return
    }

    foreach( $destDir in $DestinationDirectory )
    {
        foreach($sourceFile in $Path)
        {
            Write-WhiskeyInfo -Context $TaskContext -Message ('{0} -> {1}' -f $sourceFile,$destDir)
            Copy-Item -Path $sourceFile -Destination $destDir
        }
    }
}

