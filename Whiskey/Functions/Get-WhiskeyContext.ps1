
function Get-WhiskeyContext
{
    [CmdletBinding()]
    [OutputType([Whiskey.Context])]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $timer = New-Object 'Diagnostics.Stopwatch'
    $timer.Start()

    function Write-Timing
    {
        param(
            [string]$Message
        )

        $DebugPreference = 'Continue'
        Write-Debug -Message ('[{0:hh":"mm":"ss"."ff}]  {1}' -f $timer.Elapsed,$Message)
    }


    Write-Timing ('Get-WhiskeyContext')
    try
    {
        [Management.Automation.CallStackFrame[]]$callstack = Get-PSCallStack
        # Skip myself.
        for( $idx = 1; $idx -lt $callstack.Length; ++$idx )
        {
            $frame = $callstack[$idx]
            $invokeInfo = $frame.InvocationInfo

            Write-Timing ('    at {0}, {1}' -f $frame.Command,$frame.Location)

            if($invokeInfo.MyCommand.ModuleName -ne 'Whiskey' )
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
                    Write-Timing ('        {0}' -f $parameterName)
                    return $value
                }
            }
        }
    }
    finally
    {
        Write-Timing ('Get-WhiskeyContext')
    }
}