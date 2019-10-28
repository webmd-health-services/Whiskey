
function Write-WhiskeyDebug
{
    [CmdletBinding()]
    param(
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        [String]$Message
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $write = $DebugPreference -notin @( [Management.Automation.ActionPreference]::Ignore, [Management.Automation.ActionPreference]::SilentlyContinue )

        if( -not $write )
        {
            return
        }
        
        $messages = $null
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
       
        Write-WhiskeyInfo -Context $Context -Message $Message -Level 'Debug'
    }

    end
    {
        if( -not $write )
        {
            return
        }
        
        if( $messages )
        {
            Write-WhiskeyInfo -Context $Context -Level 'Debug' -Message $messages
        }
    }
}
