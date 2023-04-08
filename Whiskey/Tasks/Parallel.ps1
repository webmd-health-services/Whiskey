function Invoke-WhiskeyParallelTask
{
    [CmdletBinding()]
    [Whiskey.Task('Parallel')]
    [Whiskey.RequiresPowerShellModule('ThreadJob',
                                        Version='2.0.3',
                                        ModuleInfoParameterName='ThreadJobModuleInfo',
                                        VersionParameterName='ThreadJobVersion')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Parameter(Mandatory)]
        [hashtable] $TaskParameter,

        [TimeSpan] $Timeout = (New-TimeSpan -Minutes 10)
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $queues = $TaskParameter['Queues']
    if( -not $queues )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property "Queues" is mandatory. It should be an array of queues to run. Each queue should contain a "Tasks" property that is an array of task to run, e.g.

    Build:
    - Parallel:
        Queues:
        - Tasks:
            - TaskOne
            - TaskTwo
        - Tasks:
            - TaskOne

'
        return
    }

    try
    {

        $jobs = New-Object 'Collections.ArrayList'
        $queueIdx = -1
        $numTimedOut = 0

        foreach( $queue in $queues )
        {
            $queueIdx++
            $whiskeyModulePath = Join-Path -Path $whiskeyScriptRoot -ChildPath 'Whiskey.psd1' -Resolve

            if( -not $queue.ContainsKey('Tasks') )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Queue[{0}]: Property "Tasks" is mandatory. Each queue should have a "Tasks" property that is an array of Whiskey task to run, e.g.

    Build:
    - Parallel:
        Queues:
        - Tasks:
            - TaskOne
            - TaskTwo
        - Tasks:
            - TaskOne

    ' -f $queueIdx);
                return
            }

            Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}]  Starting background queue.' -f $queueIdx)

            $serializableContext = $TaskContext | ConvertFrom-WhiskeyContext

            $taskPathsTasks =
                $queue['Tasks'] |
                ForEach-Object {
                    $taskName,$taskParameter = ConvertTo-WhiskeyTask -InputObject $_ -ErrorAction Stop
                    [pscustomobject]@{
                        Name = $taskName;
                        Parameter = $taskParameter
                    }
                }

            $taskModulePaths =
                Get-WhiskeyTask |
                ForEach-Object { Get-Command -Name $_.CommandName } |
                Select-Object -ExpandProperty 'Module' |
                Select-Object -ExpandProperty 'Path' |
                Select-Object -Unique
            if( $taskModulePaths )
            {
                $msg = "Found $(($taskModulePaths | Measure-Object).Count) module(s) containing Whiskey tasks:"
                Write-WhiskeyDebug -Context $TaskContext -Message $msg
                $taskModulePaths | ForEach-Object { "* $($_)" } | Write-Debug
            }
            else
            {
                Write-WhiskeyDebug -Context $TaskContext -Message 'Found no loaded modules that contain Whiskey tasks.'
            }

            Write-WhiskeyInfo -Context $TaskContext -Message "Starting background job #$($queueIdx)."
            $job = Start-Job -ScriptBlock {

                    Set-StrictMode -Version 'Latest'

                    # Progress bars in background jobs seem to cause problems.
                    $Global:ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
                    $VerbosePreference = $using:VerbosePreference
                    $DebugPreference = $using:DebugPreference
                    $InformationPreference = $using:InformationPreference
                    $WarningPreference = $using:WarningPreference
                    $ErrorActionPreference = $using:ErrorActionPreference

                    $whiskeyModulePath = $using:whiskeyModulePath
                    $serializedContext = $using:serializableContext

                    & {
                        Import-Module -Name $whiskeyModulePath
                    } 4> $null

                    [Whiskey.Context]$context = $serializedContext | ConvertTo-WhiskeyContext

                    # Load third-party tasks.
                    foreach( $info in $context.TaskPaths )
                    {
                        Write-WhiskeyDebug -Context $context -Message ('Loading task from "{0}".' -f $info.FullName)
                        . $info.FullName
                    }

                    # Load modules containing third-party tasks.
                    foreach( $modulePath in $using:taskModulePaths )
                    {
                        Write-WhiskeyDebug -Context $context -Message "Loading task module ""$($modulePath)""."
                        Import-Module -Name $modulePath -Global
                    }

                    foreach( $task in $using:taskPathsTasks )
                    {
                        Write-WhiskeyDebug -Context $context -Message ($task.Name)
                        $task.Parameter | ConvertTo-Json -Depth 50 | Write-WhiskeyDebug -Context $context
                        Invoke-WhiskeyTask -TaskContext $context -Name $task.Name -Parameter $task.Parameter
                    }
                }

            $job | Add-Member -MemberType NoteProperty -Name 'QueueIndex' -Value $queueIdx
            [Void]$jobs.Add($job)
        }

        $taskDuration = [Diagnostics.Stopwatch]::StartNew()
        foreach( $job in $jobs )
        {
            $msg = "Watching background job #$($job.QueueIndex) $($job.Name)."
            Write-WhiskeyInfo -Context $TaskContext -Message $msg
            Write-WhiskeyDebug -Context $TaskContext -Message "Job #$($job.QueueIndex) $($job.Name)"
            do
            {
                Write-WhiskeyDebug -Context $TaskContext -Message "  Waiting for 9 seconds."
                $completedJob = $job | Wait-Job -Timeout 9
                if( $job.HasMoreData )
                {
                    Write-WhiskeyDebug -Context $TaskContext -Message "  Receiving output."
                    # There's a bug where Write-Host output gets duplicated by Receive-Job if $InformationPreference is set to "Continue".
                    # Since some things use Write-Host, this is a workaround to avoid seeing duplicate host output.
                    $job | Receive-Job -InformationAction SilentlyContinue
                }
                if( $completedJob )
                {
                    $duration = $job.PSEndTime - $job.PSBeginTime
                    $msg = "Background job #$($job.QueueIndex) $($job.Name) is ""$($job.State.ToString())"" in " +
                           "$([int]$duration.TotalMinutes)m$($duration.Seconds)s."
                    Write-WhiskeyInfo -Context $TaskContext -Message $msg
                    if( $job.JobStateInfo.State -ne [Management.Automation.JobState]::Completed )
                    {
                        $msg = "Background job #$($job.QueueIndex) $($job.Name) didn't finish successfully but ended " +
                               "in state ""$($job.State.ToString())""."
                        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                        return
                    }

                    break
                }

                if( $taskDuration.Elapsed -gt $Timeout )
                {
                    $duration = (Get-Date) - $job.PSBeginTime
                    $msg = "Background job #$($job.QueueIndex) $($job.Name) is still running after " +
                           "$([int]$duration.TotalMinutes)m$($duration.Seconds)s which is longer than the " +
                           "$([int]$Timeout.TotalMinutes)m$($Timeout.Seconds)s timeout. It's final state is " +
                           """$($job.State.ToString())""."
                    Write-WhiskeyError -Context $TaskContext -Message $msg
                    $numTimedOut += 1
                    break
                }
            }
            while( $true )
        }

        if( $numTimedOut )
        {
            $msg = "$($numTimedOut) background jobs timed out without completing in $([int]$Timeout.TotalMinutes)m" +
                   "$($Timeout.Seconds)s."
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }
    }
    finally
    {
        $jobs | Stop-Job
        $jobs | Remove-Job
    }
}
