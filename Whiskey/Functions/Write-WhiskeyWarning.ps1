
function Write-WhiskeyWarning
{
    <#
    .SYNOPSIS
    Logs warning messages.

    .DESCRIPTION
    The `Write-WhiskeyWarning` function writes warning messages during a build using PowerShell's `Write-Warning` cmdlet. Pass the context of the current build to the `Context` parameter and the message to write to the `Message` parameter. Messages are prefixed with the duration of the current build and the current task (if any). If the duration can't be determined, the current time is written.

    If `$WarningPreference` is `Ignore`, Whiskey drops all messages and tries to do as little as possible so logging has minimal impact. For all other warning preferences, messages are still processed and written.

    If multiple messages are piped to `Write-WhiskeyWarning`, the are grouped together. The duration and task name are written before and after the group, and each message is the group is written unchanged, indented slightly, e.g.

        [00.00.03.34]  [Log]
            My first warning message.
            My second warning  message.
        [00.00.03.46]  [Log]

    You can also log error, info, verbose, and debug messages with Whiskey's `Write-WhiskeyError`, `Write-WhiskeyInfo`, `Write-WhiskeyVerbose`, and `Write-WhiskeyDebug` functions.

    .EXAMPLE
    Write-WhiskeyWarning -Context $context -Message 'My warning!'

    Demonstrates how write a `Warning` message. In this case, something like this would be written:

        [00:00:20:93]  [Log]  My warning!

    .EXAMPLE
    $messages | Write-WhiskeyWarning -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyWarning`. If multiple messages are piped, the are grouped together like this:

        [00:00:16.39]  [Log]
            My first warning message.
            My second warning message.
        [00:00:16.58]  [Log]
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
