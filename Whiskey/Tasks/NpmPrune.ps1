
function Invoke-WhiskeyNpmPrune
{
    [Whiskey.Task('NpmPrune',Obsolete,ObsoleteMessage='The "NpmPrune" task is obsolete. It will be removed in a future version of Whiskey. Please use the "Npm" task instead.')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The context the task is running under.
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        # The parameters/configuration to use to run the task.
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Invoke-WhiskeyNpmCommand -Name 'prune' -ArgumentList '--production' -BuildRootPath $TaskContext.BuildRoot -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
}
