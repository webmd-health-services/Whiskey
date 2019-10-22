
function Write-WhiskeyVerbose
{
    <#
    .SYNOPSIS
    Writes `Verbose` level messages.

    .DESCRIPTION
    The `Write-WhiskeyVerbose` function writes `Verbose` level messages during a build with a prefix that identifies the current pipeline and task being executed.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. Optionally, you may specify a custom indentation level for the message with the `Indent` parameter. The default message indentation is 1 space.

    This function uses PowerShell's [Write-Verbose](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-verbose) cmdlet to write the message.

    .EXAMPLE
    Write-WhiskeyVerbose -Context $context -Message 'A verbose message'

    Demonstrates how write a `Verbose` message.
    #>
    [CmdletBinding()]
    param(
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        # The message to write.
        [String]$Message
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $write = $VerbosePreference -notin @( [Management.Automation.ActionPreference]::Ignore, [Management.Automation.ActionPreference]::SilentlyContinue )
        
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

        Write-WhiskeyInfo -Context $Context -Message $Message -Level 'Verbose'
    }

    end
    {
        if( -not $write )
        {
            return
        }

        if( $messages )
        {
            Write-WhiskeyInfo -Context $Context -Level 'Verbose' -Message $messages
        }
    }
}
