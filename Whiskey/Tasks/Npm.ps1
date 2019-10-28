
function Invoke-WhiskeyNpm
{
    [Whiskey.Task('Npm')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [Whiskey.RequiresTool('NodeModule::npm',PathParameterName='NpmPath',VersionParameterName='NpmVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $commandName = $TaskParameter['Command']
    if( -not $commandName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Command" is required. It should be the name of the NPM command to run. See https://docs.npmjs.com/cli#cli for a list.')
        return
    }

    Invoke-WhiskeyNpmCommand -Name $commandName -BuildRootPath $TaskContext.BuildRoot -ArgumentList $TaskParameter['Argument'] -ErrorAction Stop

}
