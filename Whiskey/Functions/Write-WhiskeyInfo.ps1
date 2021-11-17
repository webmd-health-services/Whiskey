

function Write-WhiskeyInfo
{
    <#
    .SYNOPSIS
    Logs informational messages.

    .DESCRIPTION
    The `Write-WhiskeyInfo` function writes informational messages during a build using PowerShell's `Write-Information`
    cmdlet. Pass the current build's context object to the `Context` parameter and the message to write to the `Message`
    parameter. Messages are prefixed with the duration of the current build and current task.
    
    By default, Whiskey sets the `InformationPreference` to `Continue` for all builds so all information messages will
    be visible. To hide information messages, you must call `Invoke-WhiskeyBuild` with `-InformationAction` set to
    `Ignore`.

    You may pass multiple messages to the `Message` property, or pipe messages to `Write-WhiskeyInfo`.

    If `$InformationPreference` is `Ignore`, Whiskey does no work and immediately returns.

    You can also log error, warning, verbose, and debug messages with Whiskey's `Write-WhiskeyError`,
    `Write-WhiskeyWarning`, `Write-WhiskeyVerbose`, and `Write-WhiskeyDebug` functions.

    You can use Whiskey's `Log` task to log messages at different levels.

    .EXAMPLE
    Write-WhiskeyInfo -Context $context -Message 'An info message'

    Demonstrates how write an `Info` message.

    .EXAMPLE
    $output | Write-WhiskeyInfo -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyInfo`.
    #>
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [ValidateSet('Error', 'Warning', 'Info', 'Verbose', 'Debug')]
        # INTERNAL. DO NOT USE. To log at different levels, use `Write-WhiskeyError`, `Write-WhiskeyWarning`, `Write-WhiskeyVerbose`, or `Write-WhiskeyDebug`
        [String]$Level = 'Info',

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        # The message to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
        [String[]]$Message,

        [switch]$NoIndent,

        [switch]$NoTiming
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        # Only write if absolutely necessary as it can be expensive.
        # Since silent errors, warnings, and info can be captured, we still have to output when their prefs are silent.
        # Silent verbose and debug messages are currently capturable, so don't even bother to write them.
        $write = ($Level -eq 'Error' -and $ErrorActionPreference -ne [Management.Automation.ActionPreference]::Ignore) -or 
                 ($Level -eq 'Warning' -and $WarningPreference -ne [Management.Automation.ActionPreference]::Ignore) -or
                 ($Level -eq 'Info' -and $InformationPreference -ne [Management.Automation.ActionPreference]::Ignore) -or
                 ($Level -eq 'Verbose' -and $VerbosePreference -notin @([Management.Automation.ActionPreference]::Ignore,[Management.Automation.ActionPreference]::SilentlyContinue)) -or
                 ($Level -eq 'Debug' -and $DebugPreference -notin @([Management.Automation.ActionPreference]::Ignore,[Management.Automation.ActionPreference]::SilentlyContinue))

        if( -not $write )
        {
            return
        }

        $isError = $Level -eq 'Error'
        $errorMsgs = [Collections.ArrayList]::New()

        if( $isError )
        {
            return
        }

        $isInfo = $Level -eq 'Info'

        $writeCmd = 'Write-{0}' -f $Level
        if( $isInfo )
        {
            $writeCmd = 'Write-Information'
        }

        if( -not $Context )
        {
            $Context = Get-WhiskeyContext
        }

        $prefix = ''

        $indent = $taskWriteIndent
        if( $NoIndent -or -not $isInfo )
        {
            $indent = ''
        }
    }

    process
    {
        if( -not $write )
        {
            return
        }

        foreach( $msg in $Message )
        {
            if( $isError )
            {
                [void]$errorMsgs.Add($msg)
                continue
            }

            if( -not $isInfo )
            {
                & $writeCmd $msg
                continue
            }

            $prefix = ''
            if( -not $NoTiming )
            {
                if( $Context )
                {
                    $prefix =
                        "[$($Context.BuildStopwatch | Format-Stopwatch)]  [$($Context.TaskStopwatch | Format-Stopwatch)]"
                }
                else
                {
                    $prefix = "[$((Get-Date).ToString('HH:mm:ss'))]"
                }
            }

            $separator = '  '
            $thisMsgIndent = $indent
            if( -not $msg )
            {
                $separator = ''
                $thisMsgIndent = ''
            }

            & $writeCmd "$($prefix)$($separator)$($thisMsgIndent)$($msg)"
        }
    }

    end
    {
        if( $write -and $isError -and $errorMsgs.Count )
        {
            $errorMsg = $errorMsgs -join [Environment]::NewLine
            Write-Host "ErrorActionPreference  $($ErrorActionPreference)"
            if( $ErrorActionPreference -ne [Management.Automation.ActionPreference]::SilentlyContinue )
            {
                # Write the error message to stderr so we have full control of what it looks like (i.e. it doesn't show
                # errors using PowerShell's terrible error view). Besides, in a build tool, stack traces are only 
                # useful for Whiskey developers, not people trying to figure out why/how their build broke.
                #
                # This error can *not* be caught *or* redirected by PowerShell since it is bypassing PowerShell's streams
                # and going direct to STDERR.
                $Host.UI.WriteErrorLine($errorMsg)
            }
            # Still make sure it appears in the global error variable.
            Write-Error -Message $errorMsg -ErrorAction ([Management.Automation.ActionPreference]::SilentlyContinue)
        }
    }
}
