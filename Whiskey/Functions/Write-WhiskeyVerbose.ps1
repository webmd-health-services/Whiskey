
function Write-WhiskeyVerbose
{
    <#
    .SYNOPSIS
    Logs verbose messages.

    .DESCRIPTION
    The `Write-WhiskeyVerbose` function writes verbose messages with PowerShell's `Write-Verbose` cmdlet. Pass the
    context of the current build to the `Context` parameter and the message to log to the `Message` parameter. Each
    message is prefixed with the duration of the current build and current task. Multiple messages may be passed to the
    `Message` parameter or piped to `Write-WhiskeyVerbose`.

    If `$VerbosePreference` is set to `SilentlyContinue` or `Ignore`, `Write-WhiskeyVerbose` does no work and
    immediately returns

    To see verbose messages in your build output, use the `-Verbose` switch when running your build.

    You can also log error, warning, info, and debug messages with Whiskey's `Write-WhiskeyError`,
    `Write-WhiskeyWarning`, `Write-WhiskeyInfo`, and `Write-WhiskeyDebug` functions.

    .EXAMPLE
    Write-WhiskeyVerbose -Context $context -Message 'My verbose message'

    Demonstrates how to write a verbose message.

    .EXAMPLE
    $messages | Write-WhiskeyVerbose -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyVerbose`.
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
