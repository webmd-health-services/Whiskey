
function Format-WhiskeyMessage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [String]$Message,

        [int]$Indent = 0
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    ('[{0}][{1}][{2}]  {3}{4}' -f $Context.PipelineName,$Context.TaskIndex,$Context.TaskName,(' ' * ($Indent * 2)),$Message)
}
