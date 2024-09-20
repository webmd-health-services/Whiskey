
function Invoke-WhiskeyNpm
{
    [Whiskey.Task('Npm',
        Obsolete,
        ObsoleteMessage='The "Npm" task is obsolete and will be removed in a future version of Whiskey. Instead, ' +
                        'install a global version of Node.js and add the npm commands to run to your whiskey.yml ' +
                        'script. If you want to install a local copy of Node.js, use the "InstallNode" task, which ' +
                        'will add Node.js commands to your build''s PATH environment variable.')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [Whiskey.RequiresNodeModule('npm', PathParameterName='NpmPath', VersionParameterName='NpmVersion')]
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
