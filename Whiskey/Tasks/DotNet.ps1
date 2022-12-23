
function Invoke-WhiskeyDotNet
{
    [CmdletBinding()]
    [Whiskey.Task('DotNet')]
    [Whiskey.RequiresTool('DotNet', PathParameterName='DotNetPath', VersionParameterName='SdkVersion')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [switch] $NoLog
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $command = $TaskParameter['Command']
    if( -not $command )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Command" is required. It should be the name of the dotnet.exe command to run, e.g. "build", "test", etc.')
        return
    }

    $dotnetExe = $TaskParameter['DotNetPath']

    $invokeParameters = @{
        TaskContext = $TaskContext;
        Name = $command;
        ArgumentList = $TaskParameter['Argument'];
        NoLog = $NoLog;
    }

    if ( $TaskParameter.ContainsKey('DotNetPath') )
    {
        $invokeParameters['DotNetPath'] = $TaskParameter['DotNetPath']
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message ('.NET Core SDK {0}' -f (& $dotnetExe --version))

    if( $TaskParameter.ContainsKey('Path') )
    {
        $projectPaths =
            $TaskParameter['Path'] |
            Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path' -PathType 'File' -AllowNonexistent
        if( -not $projectPaths -and (Get-Location).Path -ne $TaskContext.BuildRoot )
        {
            Push-Location $TaskContext.BuildRoot
            try
            {
                $projectPaths =
                    $TaskParameter['Path'] |
                    Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path' -PathType 'File' |
                    Resolve-Path |
                    Select-Object -ExpandProperty 'ProviderPath'
            }
            finally
            {
                Pop-Location
            }

            if( $projectPaths )
            {
                Write-WhiskeyWarning -Context $TaskContext -Message ('Property Path: Paths are now resolved relative to a task''s working directory, not the build root. Please update the paths in your whiskey.yml file so they are relative to the DotNet task''s working directory.')
                $projectPaths = $projectPaths | Resolve-Path -Relative
            }
        }

        foreach( $projectPath in $projectPaths )
        {
            Invoke-WhiskeyDotNetCommand @invokeParameters -ProjectPath $projectPath
        }
    }
    else
    {
        Invoke-WhiskeyDotNetCommand @invokeParameters
    }
}
