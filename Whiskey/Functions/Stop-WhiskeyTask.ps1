
function Stop-WhiskeyTask
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [String]$Message,

        [String]$PropertyName,

        [String]$PropertyDescription
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( -not ($PropertyDescription) )
    {
        $PropertyDescription = 'Build[{0}]: Task "{1}"' -f $TaskContext.TaskIndex,$TaskContext.TaskName
    }

    if( $PropertyName )
    {
        $PropertyName = ': Property "{0}"' -f $PropertyName
    }

    if( $ErrorActionPreference -ne 'Ignore' )
    {
        throw '{0}: {1}{2}: {3}' -f $TaskContext.ConfigurationPath,$PropertyDescription,$PropertyName,$Message
    }
}
