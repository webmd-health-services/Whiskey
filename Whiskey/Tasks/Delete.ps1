function Remove-WhiskeyItem
{
    [Whiskey.TaskAttribute('Delete',SupportsClean)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,AllowNonexistent)]
        [String[]]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    foreach( $pathItem in $Path )
    {
        if( -not (Test-Path -Path $pathItem) )
        {
            continue
        }

        Remove-WhiskeyFileSystemItem -Path $pathitem -ErrorAction Stop
    }
}