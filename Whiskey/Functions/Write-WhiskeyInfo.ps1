

function Write-WhiskeyInfo
{
    <#
    .SYNOPSIS
    Writes Whiskey messages.

    .DESCRIPTION
    The `Write-WhiskeyInfo` function writes messages during a build. It prefixes each message with the amount of time since the build started, the message level, and the name of the current task. 
    
    Whiskey has five levels of messages: `Error`, `Warning`, `Info`, `Verbose`, and `Debug`. Messages at each level or only shown if their corresponding PowerShell preference variable is set to `Continue` or `Inquire`, e.g.

    * `Error`: `$ErrorActionPreference`
    * `Warning`: `$WarningPreference`
    * `Info`: `$InformationPreference`
    * `Verbose`: `$VerbosePreference`
    * `Debug`: `$DebugPreference`

    By default, this function writes at the `Info` level. To write at specific levels, we recommend using these functions:

    * `Write-WhiskeyError`
    * `Write-WhiskeyWarning`
    * `Write-WhiskeyVerbose`
    * `Write-WhiskeyDebug`

    No matter the level, *all* messages are written to PowerShell's information stream using PowerShell's `Write-Information` preference.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. If you don't pass a context object, this function will look up the call stack to find the context for the currently executing build.

    .EXAMPLE
    Write-WhiskeyInfo -Context $context -Message 'An info message'

    Demonstrates how write an `Info` message.
    #>
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [ValidateSet('Error','Warning','Info','Verbose','Debug')]
        # The log level.
        [String]$Level = 'Info',

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        # The message to log.
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
