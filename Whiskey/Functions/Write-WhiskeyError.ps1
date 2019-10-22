
function Write-WhiskeyError
{
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        [String]$Message
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        
        $write = $ErrorActionPreference -ne [Management.Automation.ActionPreference]::Ignore

        if( -not $write )
        {
            return
        }

        [Collections.ArrayList]$messages = $null
        if( $PSCmdlet.MyInvocation.ExpectingInput )
        {
            $messages = [Collections.ArrayList]::new()
        }
    }

    process
    {
        if( -not $write )
        {
            return
        }

        if( $PSCmdlet.MyInvocation.ExpectingInput )
        {
            [Void]$messages.Add($Message)
            return
        }

        Write-WhiskeyInfo -Context $Context -Level Error -Message $Message
    }

    end
    {
        if( -not $write )
        {
            return
        }

        if( $messages )
        {
            Write-WhiskeyInfo -Context $Context -Level Error -Message $messages
        }
    }
}
