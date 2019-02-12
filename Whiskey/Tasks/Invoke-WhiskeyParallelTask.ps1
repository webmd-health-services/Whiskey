
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
            $whiskeyModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey.psd1' -Resolve

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

            $job = Start-Job -Name $queueIdx -ScriptBlock {

                    Set-StrictMode -Version 'Latest'

                    $VerbosePreference = $using:VerbosePreference
                    $DebugPreference = $using:DebugPreference
                    $ProgressPreference = $using:ProgressPreference
                    $whiskeyModulePath = $using:whiskeyModulePath
                    $serializedContext = $using:serializableContext

                    & {
                        Import-Module -Name $whiskeyModulePath
                    } 4> $null

                    [Whiskey.Context]$context = $serializedContext | ConvertTo-WhiskeyContext

                    # Load third-party tasks.
                    foreach( $info in $context.TaskPaths )
                    {
                        Write-Verbose ('Loading tasks from "{0}".' -f $info.FullName)
                        . $info.FullName
                    }

                    $moduleRoot = $whiskeyModulePath | Split-Path
                    . (Join-Path -Path $moduleRoot -ChildPath 'Functions\Use-CallerPreference.ps1' -Resolve)
                    . (Join-Path -Path $moduleRoot -ChildPath 'Functions\ConvertTo-WhiskeyTask.ps1' -Resolve)

                    $tasks = $using:queue['Tasks']
                    foreach( $task in $tasks )
                    {
                        $taskName,$taskParameter = ConvertTo-WhiskeyTask -InputObject $task -ErrorAction Stop
                        Write-Debug -Message ($taskName)
                        $taskParameter | ConvertTo-Json -Depth 50 | Write-Debug
                        Invoke-WhiskeyTask -TaskContext $context -Name $taskName -Parameter $taskParameter
                    }
                }

                $job |
                    Add-Member -MemberType NoteProperty -Name 'QueueIndex' -Value $queueIdx -PassThru |
                    Add-Member -MemberType NoteProperty -Name 'Completed' -Value $false
                [void]$jobs.Add($job)
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
                    $completedJob | Receive-Job
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