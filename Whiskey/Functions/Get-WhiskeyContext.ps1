
function Get-WhiskeyContext
{
    [CmdletBinding()]
    [OutputType([Whiskey.Context])]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    [Management.Automation.CallStackFrame[]]$callstack = Get-PSCallStack
    # Skip myself.
    for( $idx = 1; $idx -lt $callstack.Length; ++$idx )
    {
        $frame = $callstack[$idx]
        $invokeInfo = $frame.InvocationInfo

        if( -not $invokeInfo.MyCommand -or $invokeInfo.MyCommand.ModuleName -ne 'Whiskey' )
        {
            # Nice try!
            continue
        }

        $frameParams = $invokeInfo.BoundParameters
        foreach( $parameterName in $frameParams.Keys )
        {
            $value = $frameParams[$parameterName]
            if( $null -ne $value -and $value -is [Whiskey.Context] )
            {
                return $value
            }
        }
    }
}