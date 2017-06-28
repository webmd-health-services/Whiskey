
function Stop-WhiskeyTask
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # An object
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        $Message,

        [string]
        $PropertyDescription
    )

    Set-StrictMode -Version 'Latest'

    if( -not ($PropertyDescription) )
    {
        $PropertyDescription = 'BuildTasks[{0}]: {1}' -f $TaskContext.TaskIndex,$TaskContext.TaskName
    }

    throw '{0}: {1}: {2}' -f $TaskContext.ConfigurationPath,$PropertyDescription,$Message
}
