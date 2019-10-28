

function Write-WhiskeyInfo
{
    <#
    .SYNOPSIS
    Logs informational messages.

    .DESCRIPTION
    The `Write-WhiskeyInfo` function writes informational messages during a build using PowerShell's `Write-Information` cmdlet. Pass the current build's context object to the `Context` parameter and the message to write to the `Message` parameter. By default, Whiskey sets the `InformationPreference` to `Continue` for all builds so all information messages will typically be visible. To hide information messages, you must call `Invoke-WhiskeyBuild` with `-InformationAction` set to `Ignore`.

    Messages are prefixed with the duration of the current build and the current task's name (if any) e.g.

         [00:00:10.45]  [Task]  My message!

    If the duration of the current build can't be determined, the current time is written instead.

    If you pass in multiple messages to the `Message` parameter or pipe multiple messages in, the timestamp and task name are written, then each messages (indented four spaces), followed by another line with the duration and task name.

         [00:00:10.45]  [Task]
             My first message.
             My second message.
         [00:00:10.45]  [Task]

    If `$InformationPrefernce` is `Ignore`, Whiskey drops all messages as quickly as possible. It tries to do as little work so that logging has minimal affect. For all other information preference values, each message is processed and written. 

    You can also log error, warning, verbose, and debug messages with Whiskey's `Write-WhiskeyError`, `Write-WhiskeyWarning`, `Write-WhiskeyVerbose`, and `Write-WhiskeyDebug` functions.

    You can use Whiskey's `Log` task to log messages at different levels.

    .EXAMPLE
    Write-WhiskeyInfo -Context $context -Message 'An info message'

    Demonstrates how write an `Info` message. In this case, something like this would be written:

        [00:00:20:93]  [Log]  An info message

    .EXAMPLE
    $output | Write-WhiskeyInfo -Context $context

    Demonstrates that you can pipe messages to `Write-WhiskeyInfo`. If multiple messages are piped, the are grouped together like this:

        [00:00:16.39]  [Log]
            My first info message.
            My second info message.
        [00:00:16.58]  [Log]
    #>
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [ValidateSet('Error','Warning','Info','Verbose','Debug')]
        # INTERNAL. DO NOT USE. To log at different levels, use `Write-WhiskeyError`, `Write-WhiskeyWarning`, `Write-WhiskeyVerbose`, or `Write-WhiskeyDebug`
        [String]$Level = 'Info',

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        # The message to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
        [String[]]$Message
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

        if( -not $context )
        {
            $context = Get-WhiskeyContext
        }

        $messages = New-Object 'Collections.ArrayList'

        $task = ''
        if( -not $context )
        {
            $duration = (Get-Date).ToString('HH:mm:ss.ff')
        }
        else
        {
            $duration = ((Get-Date) - $context.StartedAt).ToString('hh":"mm":"ss"."ff')
            if( $context.TaskName )
            {
                $task = '  [{0}]' -f $context.TaskName
            }
        }
    }

    process
    {
        if( -not $write )
        {
            return
        }

        if( $Message.Length -eq 0 )
        {
            return
        }

        foreach( $item in $Message )
        {
            [Void]$messages.Add($item)
        }
    }

    end
    {
        if( -not $write -or $messages.Count -lt 1 )
        {
            return
        }

        if( $Level -eq 'Error' )
        {
            $errorMsg = $messages -join [Environment]::NewLine
            Write-Error -Message $errorMsg
            return
        }

        $messagesToWrite = New-Object 'Collections.ArrayList' ($messages.Count + 2)
        $prefix = '[{0}]{1}' -f $duration,$task
        if( $messages.Count -gt 1 )
        {
            [Void]$messagesToWrite.Add($prefix)
            $indent = '    '
            foreach( $item in $Messages )
            {
                [Void]$messagesToWrite.Add(('{0}{1}' -f $indent,$item))
            }
            [Void]$messagesToWrite.Add($prefix)
        }
        else
        {
            [Void]$messagesToWrite.Add(('{0}  {1}' -f $prefix,$messages[0]))
        }

        $writeCmd = 'Write-{0}' -f $Level
        if( $Level -eq 'Info' )
        {
            $writeCmd = 'Write-Information'
        }

        foreach( $messageToWrite in $messagesToWrite )
        {
            & $writeCmd $messageToWrite
        }
    }
}
