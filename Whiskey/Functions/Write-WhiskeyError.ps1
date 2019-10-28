
function Write-WhiskeyError
{
    <#
    .SYNOPSIS
    Logs error messages.

    .DESCRIPTION
    The `Write-WhiskeyError` function writes error messages using `Write-Error`. Pass the context of the current build to the `Context` parameter and the message you want to write to the `Message` parameter. Error messages are prefixed with the duration of the current build and the current task name (if any). If the duration of the current build can't be determined, the current time is written instead.
    
    By default, error messages do not stop a build. If you want to log an error *and* fail/stop a build, use `Stop-WhiskeyTask`.

    If `$ErrorActionPreference` is `Ignore`, Whiskey drops all messages and tries to do as little as possible so logging has minimal impact. For all other error action preferences, messages are still processed and written.

    Whiskey ships with its own error output formatter that will show the entire script stack trace of an error. You'll get this view even if you don't use `Write-WhiskeyError`.

    You can also log warning, info, verbose, and debug messages with Whiskey's `Write-WhiskeyWarning`, `Write-WhiskeyInfo`, `Write-WhiskeyVerbose`, and `Write-WhiskeyDebug` functions.

    .EXAMPLE
    Write-WhiskeyError -Context $context -Message 'Something bad happened!'

    Demonstrates how to write an error.

    .EXAMPLE
    $errors | Write-WhiskeyError -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyError`.
    #>
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        # The message to write. Each message is written to the user with `Write-Error`.
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
