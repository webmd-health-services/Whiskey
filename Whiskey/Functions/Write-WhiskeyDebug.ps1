
function Write-WhiskeyDebug
{
    <#
    .SYNOPSIS
    Logs debug messages.

    .DESCRIPTION
    The `Write-WhiskeyDebug` function writes debug messages using PowerShell's `Write-Debug` cmdlet. Pass the context
    of the current build to the `Context` parameter and the message to write to the `Message` parameter. Messages are
    prefixed with the duration of the current build and curren task. If the duration can't be determined, the current
    time is used.

    If `$DebugPreference` is set to `SilentlyContinue` or `Ignore`, `Write-WhiskeyDebug` immediately returns.

    You can pass messages to the `Message` parameter, or pipe messages to `Write-WhiskeyDebug`.

    To view debug messages in your build output, you'll need to set the global `DebugPreference` variable to `Continue`.

    You can also log error, warning, info, and verbose messages with Whiskey's `Write-WhiskeyError`,
    `Write-WhiskeyWarning`, `Write-WhiskeyInfo`, and `Write-WhiskeyVerbose` functions.

    .EXAMPLE
    Write-WhiskeyDebug -Context $context -Message 'My debug message'

    Demonstrates how to write a debug message.

    .EXAMPLE
    $messages | Write-WhiskeyDebug -Context $context

    Demonstrates how to pipe messages to `Write-WhiskeyDebug`. 
    #>
    [CmdletBinding(DefaultParameterSetName='NoIndent')]
    param(
        # The context of the current build.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        # The message to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
        [String]$Message,

        [Parameter(Mandatory, ParameterSetName='Indent')]
        [switch] $Indent,

        [Parameter(Mandatory, ParameterSetName='Outdent')]
        [switch] $Outdent
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( $Outdent )
        {
            $script:indentLevel -= 1
        }

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

        if( $indentLevel -gt 0 )
        {
            $prefix = ' ' * ($indentLevel * 4)
            foreach( $line in ($Message -split '\n\r?') )
            {
                $newMsg = "$($prefix)$($line)"

                if( $PSCmdlet.MyInvocation.ExpectingInput )
                {
                    [void]$messages.Add($newMsg)
                    return
                }
            
                Write-WhiskeyInfo -Context $Context -Message $newMsg -Level 'Debug'
            }

            return
        }
        
        if( $PSCmdlet.MyInvocation.ExpectingInput )
        {
            [void]$messages.Add($Message)
            return
        }
       
        Write-WhiskeyInfo -Context $Context -Message $Message -Level 'Debug'
    }

    end
    {
        try
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
        finally
        {
            if( $Indent )
            {
                $script:indentLevel += 1
            }
        }
    }
}
