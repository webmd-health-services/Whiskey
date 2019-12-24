
function Invoke-WhiskeyParallelTask
{
    [CmdletBinding()]
    [Whiskey.Task('Parallel')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
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

            $tasks = 
                $queue['Tasks'] |
                ForEach-Object { 
                    $taskName,$taskParameter = ConvertTo-WhiskeyTask -InputObject $_ -ErrorAction Stop
                    [pscustomobject]@{
                        Name = $taskName;
                        Parameter = $taskParameter
                    }
                }
            $job = Start-Job -Name $queueIdx -ScriptBlock {

                    Set-StrictMode -Version 'Latest'

                    $VerbosePreference = $using:VerbosePreference
                    $DebugPreference = $using:DebugPreference
                    $ProgressPreference = $using:ProgressPreference
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
                        Write-WhiskeyVerbose -Context $context -Message ('Loading tasks from "{0}".' -f $info.FullName)
                        . $info.FullName
                    }

                    foreach( $task in $using:tasks )
                    {
                        Write-WhiskeyDebug -Context $context -Message ($task.Name)
                        $task.Parameter | ConvertTo-Json -Depth 50 | Write-WhiskeyDebug -Context $context
                        Invoke-WhiskeyTask -TaskContext $context -Name $task.Name -Parameter $task.Parameter
                    }
                }

                $job |
                    Add-Member -MemberType NoteProperty -Name 'QueueIndex' -Value $queueIdx -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'Completed' -Value $false
                [Void]$jobs.Add($job)
        }

        $lastNotice = (Get-Date).AddSeconds(-61)
        while( $jobs | Where-Object { -not $_.Completed } )
        {
            foreach( $job in $jobs )
            {
                if( $job.Completed )
                {
                    continue
                }

                if( $lastNotice -lt (Get-Date).AddSeconds(-60) )
                {
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}][{1}]  Waiting for queue.' -f $job.QueueIndex,$job.Name)
                    $notified = $true
                }

                $completedJob = $job | Wait-Job -Timeout 1
                if( $completedJob )
                {
                    $job.Completed = $true
                    # There's a bug where Write-Host output gets duplicated by Receive-Job if $InformationPreference is set to "Continue".
                    # Since some things use Write-Host, this is a workaround to avoid seeing duplicate host output.
                    $completedJob | Receive-Job -InformationAction SilentlyContinue
                    $duration = $job.PSEndTime - $job.PSBeginTime
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('[{0}][{1}]  {2} in {3}' -f $job.QueueIndex,$job.Name,$job.State.ToString().ToUpperInvariant(),$duration)
                    if( $job.JobStateInfo.State -eq [Management.Automation.JobState]::Failed )
                    {
                        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Queue[{0}] failed. See previous output for error information.' -f $job.Name)
                        return
                    }
                }
            }

            if( $notified )
            {
                $notified = $false
                $lastNotice = Get-Date
            }
        }
    }
    finally
    {
        $jobs | Stop-Job
        $jobs | Remove-Job
    }
}
