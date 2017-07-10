
function Unregister-WhiskeyEvent
{
    <#
    .SYNOPSIS
    Unregisters a command to call when specific events happen during a build.

    .DESCRIPTION
    The `Unregister-WhiskeyEvent` function unregisters a command to run when a specific event happens during a build. This function is paired with `Register-WhiskeyEvent'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the command to run during the event.
        $CommandName,

        [Parameter(Mandatory=$true)]
        [string]
        [ValidateSet('BeforeTask','AfterTask')]
        # When the command should be run; what events does it respond to?
        $Event
    )

    Set-StrictMode -Version 'Latest'

    if( -not $events[$Event] )
    {
        return
    }

    if( -not $Events[$Event].Contains( $CommandName ) )
    {
        return
    }

    $events[$Event].Remove( $CommandName )
}