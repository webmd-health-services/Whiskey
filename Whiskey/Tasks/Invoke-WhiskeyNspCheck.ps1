
function Invoke-WhiskeyNspCheck
{
    <#
    .SYNOPSIS
    Runs the Node Security Platform against a module's dependenices.
    
    .DESCRIPTION
    The `NspCheck` task runs `node.exe nsp check`, the Node Security Platform, which checks a `package.json` and `npm-shrinkwrap.json` for known security vulnerabilities against the Node Security API. The latest version of the NSP module is installed into a dedicated Node environment you can find in a .node directory in the same directory as your whiskey.yml file. If any security vulnerabilties are found, the NSP module returns a non-zero exit code which will fail the task.

    You must specify what version of Node.js you want in the engines field of your package.json file. (See https://docs.npmjs.com/files/package.json#engines for more information.) The version of Node is installed into a .node directory in the same directory as your whiskey.yml file.

    If the application's `package.json` file does not exist in the build root next to the `whiskey.yml` file, specify a `WorkingDirectory` where it can be found.

    This task will install the latest LTS version of Node into a `.node` directory (in the same directory as your whiskey.yml file). To use a specific version, set the `engines.node` property in your package.json file to the version you want. (See https://docs.npmjs.com/files/package.json#engines for more information.)

    # Properties

    # * `WorkingDirectory`: the directory where the `package.json` exists. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.
    # * `Version`: the version of NSP to install and utilize for security checks. Defaults to the latest stable version of NSP.

    # Examples

    ## Example 1

        BuildTasks:
        - NspCheck
    
    This example will run `node.exe nsp check` against the modules listed in the `package.json` file located in the build root.

    ## Example 2

        BuildTasks:
        - NspCheck:
            WorkingDirectory: app
    
    This example will run `node.exe nsp check` against the modules listed in the `package.json` file that is located in the `(BUILD_ROOT)\app` directory.

    ## Example 3

        BuildTasks:
        - NspCheck:
            Version: 2.7.0
    
    This example will run `node.exe nsp check` by installing and running NSP version 2.7.0.
    #>
    [Whiskey.Task("NspCheck")]
    [Whiskey.RequiresTool("Node", "NodePath")]
    [Whiskey.RequiresTool("NodeModule::nsp", "NspPath", VersionParameterName="Version")]
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

    $nspRoot = $TaskParameter['NspPath']
    if( -not $nspRoot -or -not (Test-Path -Path $nspRoot -PathType Container) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP node module not installed by Whiskey. Something pretty serious has gone wrong.')
    }

    $nspPath = Join-Path -Path $nspRoot -ChildPath 'bin\nsp' -Resolve
    if( -not $nspPath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('It looks like the latest version of NSP doesn''t have a ''{0}\bin\nsp'' script. Please use the ''Version'' property on the NspCheck task to specify a version that includes this script.' -f $nspPath)
    }

    $nodePath = $TaskParameter['NodePath']
    if( -not $nodePath -or -not (Test-Path -Path $nodePath -PathType Leaf) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey failed to install Node. Something pretty serious has gone wrong.')
    }

    Write-WhiskeyTiming -Message 'Running NSP security check'

    $formattingArg = '--output'
    $isNsp3 = -not $TaskParameter.ContainsKey('Version') -or -not $TaskParameter['Version'] -match '^(0|1|2)\.'
    if( $isNsp3 )
    {
        $formattingArg = '--reporter'
    }

    $output = Invoke-Command -NoNewScope -ScriptBlock {
        param(
            $JsonOutputFormat
        )

        & $nodePath $nspPath 'check' $JsonOutputFormat 'json' 2>&1 |
            ForEach-Object { if( $_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
    } -ArgumentList $formattingArg

    Write-WhiskeyTiming -Message 'COMPLETE'

    try
    {
        $results = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    }
    catch
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, did not run successfully as it did not return valid JSON (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$output)
    }

    if ($Global:LASTEXITCODE -ne 0)
    {
        $summary = $results | Format-List | Out-String
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, found the following security vulnerabilities in your dependencies (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$summary)
    }
}
