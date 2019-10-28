
function Invoke-WhiskeyNpmRunScript
{
    [Whiskey.Task('NpmRunScript',Obsolete,ObsoleteMessage='The "NpmRunScriptTask" is obsolete. It will be removed in a future version of Whiskey. Please use the "Npm" task instead.')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $npmScripts = $TaskParameter['Script']
    if (-not $npmScripts)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property ''Script'' is mandatory. It should be a list of one or more npm scripts to run during your build, e.g.,

        Build:
        - NpmRunScript:
            Script:
            - build
            - test

        '
        return
    }

    foreach ($script in $npmScripts)
    {
        Write-WhiskeyDebug -Context $TaskContext -Message ('Running script ''{0}''.' -f $script)
        Invoke-WhiskeyNpmCommand -Name 'run-script' -ArgumentList $script -BuildRootPath $TaskContext.BuildRoot -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
        Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
    }
}
