
function Write-WhiskeyVerbose
{
    <#
    .SYNOPSIS
    Logs verbose messages.

    .DESCRIPTION
    The `Write-WhiskeyVerbose` function writes verbose messages with PowerShell's `Write-Verbose` cmdlet. Pass the context of the current build to the `Context` parameter and the message to log to the `Message` parameter. Each message is prefixed with the duration of the current build and the current task name (if any). If the duration can't be determined, the current time is used.

    If `$VerbosePreference` is set to `SilentlyContinue` or `Ignore`, Whiskey doesn't write anything at all. Message are silently dropped. Whiskey does its best to do as little work as possible.

    If you pipe multiple messages to `Write-WhiskeyVerbose`, they are grouped together. The duration and task name are written before and after the group. Each message in the group is then written unchanged, indented slightly, e.g.

        [00:00:08.42]  [Log]
            My first verbose message.
            My second verbose message.
        [00:00:08.52]  [Log]

    To see verbose messages in your build output, use the `-Verbose` switch when running your build.

    You can also log error, warning, info, and debug messages with Whiskey's `Write-WhiskeyError`, `Write-WhiskeyWarning`, `Write-WhiskeyInfo`, and `Write-WhiskeyDebug` functions.

    .EXAMPLE
    Write-WhiskeyVerbose -Context $context -Message 'My verbose message'

    Demonstrates how write a verbose message. In this case, something like this would be written:

        [00:00:20:93]  [Log]  My verbose message.

    .EXAMPLE
    $messages | Write-WhiskeyVerbose -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyVerbose`. If multiple messages are piped, the are grouped together like this:

        [00:00:16.39]  [Log]
            My first verbose message.
            My second verbose message.
        [00:00:16.58]  [Log]
    #>
    [CmdletBinding()]
    param(
        # The current context.
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
