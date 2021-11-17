
function Write-WhiskeyWarning
{
    <#
    .SYNOPSIS
    Logs warning messages.

    .DESCRIPTION
    The `Write-WhiskeyWarning` function writes warning messages using PowerShell's `Write-Warning` cmdlet. Pass the
    context of the current build to the `Context` parameter and the message to write to the `Message` parameter.
    Messages are prefixed with the duration of the current build and task. Multiple messages may be passed to the 
    `Message` parameter or piped to `Write-WhiskeyWarning`.

    If the `$WarningPreference` is `Ignore`, `Write-WhiskeyWarning` does no work and immediately returns.

    You can also log error, info, verbose, and debug messages with Whiskey's `Write-WhiskeyError`, `Write-WhiskeyInfo`,
    `Write-WhiskeyVerbose`, and `Write-WhiskeyDebug` functions.

    .EXAMPLE
    Write-WhiskeyWarning -Context $context -Message 'My warning!'

    Demonstrates how write a `Warning` message.

    .EXAMPLE
    $messages | Write-WhiskeyWarning -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyWarning`.
    #>
    [CmdletBinding()]
    param(
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        # The message to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
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
