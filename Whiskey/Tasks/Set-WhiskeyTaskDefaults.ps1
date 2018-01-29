
function Set-WhiskeyTaskDefaults
{
    <#
    .SYNOPSIS
    Sets default values for task properties.

    .DESCRIPTION
    The `TaskDefaults` task will set default values for Whiskey task properties. Define task defaults just as you would define the task itself, except nest it under a `TaskDefaults` task. If an invalid task name is given the build will be failed. The `TaskDefaults` task will *always* overwrite any existing task default values for a task.

    .EXAMPLE
    The following example demonstrates setting default values for the `MSBuild` task `Version` property and the `NuGetPack` task `Symbols` property.
   
        BuildTasks:
        - TaskDefaults:
            MSBuild:
                Version: 13.0
            NuGetPack:
                Symbols: true
    #>
    [CmdletBinding()]
    [Whiskey.Task("TaskDefaults",SupportsClean=$true,SupportsInitialize=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    foreach ($taskName in $TaskParameter.Keys)
    {
        foreach ($parameterName in $TaskParameter[$taskName].Keys)
        {
            Add-WhiskeyTaskDefault -Context $TaskContext -Task $taskName -Parameter $parameterName -Value $TaskParameter[$taskName][$parameterName] -Force
        }
    }
}
