
function Write-WhiskeyInfo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        # The current context.
        $Context,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]
        # The message to write.
        $Message
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $fullMessage = '[{0}][{1}][{2}]  {3}' -f $Context.PipelineName,$Context.TaskIndex,$Context.TaskName,$Message
    
    Write-Output -InputObject $fullMessage
}
