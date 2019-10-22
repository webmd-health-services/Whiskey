
function Write-WhiskeyWarning
{
    <#
    .SYNOPSIS
    Writes `Warning` level messages.

    .DESCRIPTION
    The `Write-WhiskeyWarning` function writes `Warning` level messages during a build with a prefix that identifies the current build configuration and task being executed.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. Optionally, you may specify a custom indentation level for the message with the `Indent` parameter. The default message indentation is 1 space.

    This function uses PowerShell's [Write-Warning](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-warning) cmdlet to write the message.

    .EXAMPLE
    Write-WhiskeyWarning -Context $context -Message 'A warning message'

    Demonstrates how write a `Warning` message.
    #>
    [CmdletBinding()]
    param(
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        # The message to write.
        [String]$Message
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $write = $WarningPreference -ne [Management.Automation.ActionPreference]::Ignore 

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

        Write-WhiskeyInfo -Context $Context -Level 'Warning' -Message $Message
    }

    end
    {
        if( -not $write )
        {
            return 
        }

        if( $messages )
        {
            Write-WhiskeyInfo -Context $Context -Level 'Warning' -Message $messages
        }
    }

}
