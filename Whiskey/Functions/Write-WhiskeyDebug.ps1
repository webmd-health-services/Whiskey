
function Write-WhiskeyDebug
{
    <#
    .SYNOPSIS
    Logs debug messages.

    .DESCRIPTION
    The `Write-WhiskeyDebug` function writes debug messages using PowerShell's `Write-Debug` cmdlet. Pass the context of the current build to the `Context` parameter and the message to write to the `Message` parameter. Messages are prefixed with the duration of the current build and the curren task name (if any). If the duration can't be determined, the current time is used.

    If `$DebugPreference` is set to `SilentlyContinue` or `Ignore`, Whiskey doesn't write anything at all. Message are silently dropped. Whiskey does its best to do as little work as possible.

    If you pipe multiple messages to `Write-WhiskeyDebug`, they are grouped together. The duration and task name are written before and after the group. Each message of the group is written unchanged, indented slightly, e.g.

        [00:00:16.39]  [Log]
            My first debug message.
            My second debug message.
        [00:00:16.58]  [Log]

    To view debug messages in your build output, you'll need to set the global `DebugPreference` variable to `Continue`.

    You can also log error, warning, info, and verbose messages with Whiskey's `Write-WhiskeyError`, `Write-WhiskeyWarning`, `Write-WhiskeyInfo`, and `Write-WhiskeyVerbose` functions.

    .EXAMPLE
    Write-WhiskeyDebug -Context $context -Message 'My debug message'

    Demonstrates how to write a debug message. In this case, something like this would be written:

        [00:00:20:93]  [Log]  My debug message

    .EXAMPLE
    $messages | Write-WhiskeyDebug -Context $context

    Demonstrates how to pipe messages to `Write-WhiskeyDebug`. If multiple messages are piped, the are grouped together like this:

        [00:00:16.39]  [Log]
            My first debug message.
            My second debug message.
        [00:00:16.58]  [Log]
    #>
    [CmdletBinding()]
    param(
        # The context of the current build.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        # The message to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
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
