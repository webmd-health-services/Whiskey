
function Set-WhiskeyStop
{
    [Whiskey.TaskAttribute('Stop', SupportsClean=$true)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyVerbose -Context $TaskContext -Message 'Stopping Whiskey build.'
    $TaskContext.Stop = $true
}
