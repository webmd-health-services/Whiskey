
function Format-WhiskeyMessage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]$Context,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Message,

        [int]$Indent = 0
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    ('[{0}][{1}][{2}]  {3}{4}' -f $Context.PipelineName,$Context.TaskIndex,$Context.TaskName,(' ' * ($Indent * 2)),$Message)
}
