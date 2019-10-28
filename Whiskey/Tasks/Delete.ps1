function Remove-WhiskeyItem
{
    [Whiskey.TaskAttribute('Delete',SupportsClean)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    foreach( $path in $TaskParameter['Path'] )
    {
        $path = $path | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path' -ErrorAction Ignore
        if( -not $path )
        {
            continue
        }

        foreach( $pathItem in $path )
        {
            Remove-WhiskeyFileSystemItem -Path $pathitem -ErrorAction Stop
        }
    }
}