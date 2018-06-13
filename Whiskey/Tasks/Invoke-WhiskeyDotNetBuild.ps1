
function Invoke-WhiskeyDotNetBuild
{
    [CmdletBinding()]
    [Whiskey.Task("DotNetBuild")]
    [Whiskey.RequiresTool('DotNet','DotNetPath',VersionParameterName='SdkVersion')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $dotnetExe = $TaskParameter['DotNetPath']

    $projectPaths = ''
    if ($TaskParameter['Path'])
    {
        $projectPaths = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    }

    $verbosity = $TaskParameter['Verbosity']
    if( -not $verbosity )
    {
        $verbosity = 'minimal'
    }

    $dotnetArgs = & {
        '--configuration={0}' -f (Get-WhiskeyMSBuildConfiguration -Context $TaskContext)
        '-p:Version={0}'      -f $TaskContext.Version.SemVer1.ToString()

        if ($verbosity)
        {
            '--verbosity={0}' -f $verbosity
        }

        if ($TaskParameter['OutputDirectory'])
        {
            '--output={0}' -f $TaskParameter['OutputDirectory']
        }

        if ($TaskParameter['Argument'])
        {
            $TaskParameter['Argument']
        }
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message ('.NET Core SDK {0}' -f (& $dotnetExe --version))

    foreach($project in $projectPaths)
    {
        $loggerArgs = & {
                            '/filelogger9'
                            $logFilePath = 'dotnet.build.log'
                            if( $project )
                            {
                                $logFilePath = 'dotnet.build.{0}.log' -f ($project | Split-Path -Leaf)
                            }
                            $logFilePath = Join-Path -Path $TaskContext.OutputDirectory.FullName -ChildPath $logFilePath
                            ('/flp9:LogFile={0};Verbosity=d' -f $logFilePath)
                      }


        $fullArgumentList = & {
            'build'
            $dotnetArgs
            $project
            $loggerArgs
        }

        Write-WhiskeyCommand -Context $TaskContext -Path $dotnetExe -ArgumentList $fullArgumentList

        & $dotnetExe build $dotnetArgs $loggerArgs $project 

        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('dotnet.exe failed with exit code ''{0}''' -f $LASTEXITCODE)
        }
    }
}
