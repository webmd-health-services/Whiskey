
function Write-WhiskeyInfo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        # The current context.
        $Context,

        [Parameter(Mandatory=$true)]
        [string]
        # The message to write.
        $Message
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $fullMessage = '[{0}][{1}][{2}]  {3}' -f $Context.PipelineName,$Context.TaskIndex,$Context.TaskName,$Message
    
    if( $supportsWriteInformation )
    {
         Write-Information -MessageData $fullMessage
    }
    else
    {
        Write-Output -InputObject $fullMessage
    }
}
