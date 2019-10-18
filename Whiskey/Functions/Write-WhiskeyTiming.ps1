
function Write-WhiskeyTiming
{
    [CmdletBinding()]
    param(
        $Message
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $now = Get-Date
    Write-Debug -Message ('[{0:HH:mm:ss}]  [{1:hh":"mm":"ss"."ff}]  {2}' -f $now,($now - $buildStartedAt),$Message)
}