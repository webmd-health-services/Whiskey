
function Invoke-WhiskeyParallelTask
{
    [CmdletBinding()]
    [Whiskey.Task('Parallel')]
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
    
    $tasks = $TaskParameter['Task']
    if( -not $tasks )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property "Task" is mandatory. It should be an array of tasks to run.'
    }

    $jobs = New-Object 'Collections.ArrayList'
    $taskIdx = -1
    foreach( $task in $tasks )
    {
        $taskIdx++
        $rsTaskName = $task.Keys | Select-Object -First 1
        $rsTaskParameter = $task[$rsTaskName]
        $whiskeyModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey.psd1' -Resolve

        Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}][{1}]  Starting background task.' -f $taskIdx,$rsTaskName)

        $job = Start-Job -Name $rsTaskName -ScriptBlock {

                function Sync-ObjectProperty
                {
                    param(
                        [object]
                        $Source,

                        [object]
                        $Destination,

                        [string[]]
                        $ExcludeProperty
                    )

                    $Destination.GetType().DeclaredProperties | 
                        Where-Object { $ExcludeProperty -notcontains $_.Name } |
                        Where-Object { $_.GetSetMethod($false) } |
                        Select-Object -ExpandProperty 'Name' |
                        ForEach-Object { Write-Debug ('{0}  {1} -> {2}' -f $_,$Destination.$_,$Source.$_) ; $Destination.$_ = $Source.$_ }

                }

                $VerbosePreference = $using:VerbosePreference
                $DebugPreferece = $using:DebugPreference
                $whiskeyModulePath = $using:whiskeyModulePath 
                $originalContext = $using:TaskContext
                $taskName = $using:rsTaskName
                $taskParameter = $using:rsTaskParameter

                Import-Module -Name $whiskeyModulePath
                $moduleRoot = $whiskeyModulePath | Split-Path

                . (Join-Path -Path $moduleRoot -ChildPath 'Functions\Use-CallerPreference.ps1' -Resolve)
                . (Join-Path -Path $moduleRoot -ChildPath 'Functions\New-WhiskeyContextObject.ps1' -Resolve)
                . (Join-Path -Path $moduleRoot -ChildPath 'Functions\New-WhiskeyBuildMetadataObject.ps1' -Resolve)
                . (Join-Path -Path $moduleRoot -ChildPath 'Functions\New-WhiskeyVersionObject.ps1' -Resolve)

                $buildInfo = New-WhiskeyBuildMetadataObject
                Sync-ObjectProperty -Source $originalContext.BuildMetada -Destination $buildInfo -Exclude @( 'BuildServer' )
                if( $originalContext.BuildMetadata.BuildServer )
                {
                    $buildInfo.BuildServer = $originalContext.BuildMetadata.BuildServer
                }
                
                $buildVersion = New-WhiskeyVersionObject
                Sync-ObjectProperty -Source $originalContext.Version -Destination $buildVersion -ExcludeProperty @( 'SemVer1', 'SemVer2', 'SemVer2NoBuildMetadata' )
                $buildVersion.SemVer1 = $originalContext.Version.SemVer1.ToString()
                $buildVersion.SemVer2 = $originalContext.Version.SemVer2.ToString()
                $buildVersion.SemVer2NoBuildMetadata = $originalContext.Version.SemVer2NoBuildMetadata.ToString()

                $context = New-WhiskeyContextObject
                Sync-ObjectProperty -Source $originalContext -Destination $context -ExcludeProperty @( 'BuildMetadata', 'Version' )

                $context.BuildMetadata = $buildInfo
                $context.Version = $buildVersion

                Invoke-WhiskeyTask -TaskContext $context -Name $taskName -Parameter $taskParameter
            }
            $job | Add-Member -MemberType NoteProperty -Name 'TaskIndex' -Value $taskIdx
            [void]$jobs.Add($job)
    }

    try
    {
        foreach( $job in $jobs )
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}][{1}]  Waiting for background task.' -f $job.TaskIndex,$job.Name)
            $job | Wait-Job | Receive-Job
            $duration = $job.PSEndTime - $job.PSBeginTime
            Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}][{1}]  {2} in {3}' -f $job.TaskIndex,$job.Name,$job.State.ToString().ToUpperInvariant(),$duration)
            if( $job.JobStateInfo.State -eq [Management.Automation.JobState]::Failed )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Task "{0}" failed. See previous output for error information.' -f $job.Name)
            }
        }
    }
    finally
    {
        $jobs | Stop-Job 
        $jobs | Remove-Job
    }
}