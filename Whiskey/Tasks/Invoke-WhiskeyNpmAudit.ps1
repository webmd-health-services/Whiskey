
function Invoke-WhiskeyNpmAudit
{
    [Whiskey.Task('NpmAudit')]
    [Whiskey.RequiresTool('Node','NodePath',VersionParameterName='NodeVersion')]
    [Whiskey.RequiresTool('NodeModule::npm','NpmPath',VersionParameterName='NpmVersion')]
    [CmdletBinding()]
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

    Invoke-WhiskeyNpmCommand -Name 'audit' -NodePath $TaskParameter['NodePath'] -ErrorAction Stop
}
