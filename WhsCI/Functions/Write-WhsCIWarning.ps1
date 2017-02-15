
function Write-WhsCIWarning
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # An object
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        $Message
    )

    Set-StrictMode -Version 'Latest'

    Write-Warning -Message ('{0}: BuildTasks[{1}]: {2}: {3}' -f $TaskContext.ConfigurationPath,$TaskContext.TaskIndex,$TaskContext.TaskName,$Message)
}