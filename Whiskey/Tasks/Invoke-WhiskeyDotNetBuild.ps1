
function Invoke-WhiskeyDotNetBuild
{
    [CmdletBinding()]
    [Whiskey.Task("DotNetBuild")]
    [Whiskey.RequiresTool('DotNet','DotNetPath',VersionParameterName='SdkVersion')]
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

    if ($TaskContext.ByBuildServer)
    {
        Set-Item -Path 'env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE' -Value $true
        Set-Item -Path 'env:DOTNET_CLI_TELEMETRY_OPTOUT' -Value $true
    }

    $dotnetExe = $TaskParameter['DotNetPath']

    $projectPaths = ''
    if ($TaskParameter['Path'])
    {
        $projectPaths = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    }

    $verbosity = $TaskParameter['Verbosity']
    if (-not $verbosity -and $TaskContext.ByBuildServer)
    {
        $verbosity = 'detailed'
    }

    $outputDirectory = $TaskParameter['OutputDirectory']
    if ($outputDirectory)
    {
        $outputDirectory = $outputDirectory | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'OutputDirectory' -Force
    }

    $dotnetArgs = & {
        '--configuration={0}' -f (Get-WhiskeyMSBuildConfiguration -Context $TaskContext)
        '-p:Version={0}'      -f $TaskContext.Version.SemVer1.ToString()

        if ($verbosity)
        {
            '--verbosity={0}' -f $verbosity
        }

        if ($outputDirectory)
        {
            '--output={0}' -f $outputDirectory
        }

        $TaskParameter['Argument']
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message     ('dotnet {0}' -f $dotnetExe)
    Write-WhiskeyVerbose -Context $TaskContext -Message     ('dotnet {0}' -f (& $dotnetExe --version))
    Write-WhiskeyVerbose -Context $TaskContext -Message     ('dotnet {0}' -f ($dotnetArgs | Select-Object -First 1))
    $dotnetArgs | Select-Object -Skip 1 | ForEach-Object {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('       {0}' -f $_)
    }
    Write-WhiskeyVerbose -Context $TaskContext -Message ''

    foreach($project in $projectPaths)
    {
        $infoMessage = & {
                            if( $dotnetExe -match '\ ' )
                            {
                                '&'
                            }
                            $dotnetExe
                            'build'
                            $dotnetArgs
                            $project
                        } |
                        ForEach-Object {
                            if( $_ -match '\ ' )
                            {
                                return '"{0}"' -f $_
                            }
                            return $_
                        }

        Write-WhiskeyInfo -Context $TaskContext -Message ($infoMessage -join ' ')

        & $dotnetExe build $dotnetArgs $project

        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('dotnet.exe failed with exit code ''{0}''' -f $LASTEXITCODE)
        }
    }
}
