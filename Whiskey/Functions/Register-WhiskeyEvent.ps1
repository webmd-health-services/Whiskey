
function Register-WhiskeyEvent
{
    <#
    .SYNOPSIS
    Registers a command to call when specific events happen during a build.

    .DESCRIPTION
    The `Register-WhiskeyEvent` function registers a command to run when a specific event happens during a build. Supported events are:
    
    * `BeforeTask` which runs before each task
    * `AfterTask`, which runs after each task

    `BeforeTask` and `AfterTask` event handlers must have the following parameters:

        function Invoke-WhiskeyTaskEvent
        {
            param(
                [Parameter(Mandatory)]
                [Whiskey.Context]$TaskContext,

                [Parameter(Mandatory)]
                [string]$TaskName,

                [Parameter(Mandatory)]
                [hashtable]$TaskParameter
            )
        }

    To stop a build while handling an event, call the `Stop-WhiskeyTask` function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The name of the command to run during the event.
        [string]$CommandName,

        [Parameter(Mandatory)]
        [ValidateSet('BeforeTask','AfterTask')]
        # When the command should be run; what events does it respond to?
        [string]$Event,

        # Only fire the event for a specific task.
        [string]$TaskName
    )

    Set-StrictMode -Version 'Latest'

    $eventName = $Event
    if( $TaskName )
    {
        $eventType = $Event -replace 'Task$',''
        $eventName = '{0}{1}Task' -f $eventType,$TaskName
    }

    if( -not $events[$eventName] )
    {
        $events[$eventName] = New-Object -TypeName 'Collections.Generic.List[string]'
    }

    $events[$eventName].Add( $CommandName )
}