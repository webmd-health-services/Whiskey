
function Stop-Whiskey
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # An object
        [Whiskey.Context]$Context,
              
        [Parameter(Mandatory)]
        [string]$Message
    )
              
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
              
    throw '{0}: {1}' -f $Context.ConfigurationPath,$Message
}