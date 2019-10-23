
function Set-WhiskeyVariable 
{
    [CmdletBinding()]
    [Whiskey.Task("SetVariable",SupportsClean,SupportsInitialize)]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    foreach( $key in $TaskParameter.Keys )
    {
        if( $key -match '^WHISKEY_' )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Variable ''{0}'' is a built-in Whiskey variable and can not be changed.' -f $key)
            continue
        }
        Add-WhiskeyVariable -Context $TaskContext -Name $key -Value $TaskParameter[$key]
    }
}
