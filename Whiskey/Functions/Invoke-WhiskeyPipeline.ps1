
function Invoke-WhiskeyPipeline
{
    <#
    .SYNOPSIS
    Invokes Whiskey pipelines.

    .DESCRIPTION
    The `Invoke-WhiskeyPipeline` function runs the tasks in a pipeline. Pipelines are properties in a `whiskey.yml` under which one or more tasks are defined. For example, this `whiskey.yml` file:

        BuildTasks:
        - TaskOne
        - TaskTwo
        PublishTasks:
        - TaskOne
        - Task

    Defines two pipelines: `BuildTasks` and `PublishTasks`.

    .EXAMPLE
    Invoke-WhiskeyPipeline -Context $context -Name 'BuildTasks'

    Demonstrates how to run the tasks in a `BuildTasks` pipeline. The `$context` object is created by calling `New-WhiskeyContext`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The current build context. Use the `New-WhiskeyContext` function to create a context object.
        $Context,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of pipeline to run, e.g. `BuildTasks` would run all the tasks under a property named `BuildTasks`. Pipelines are properties in your `whiskey.yml` file that are lists of Whiskey tasks to run.
        $Name,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $config = $Context.Configuration

    if( -not $config.ContainsKey($Name) )
    {
        Stop-Whiskey -Context $Context -Message ('Pipeline ''{0}'' does not exist. Create a pipeline by defining a ''{0}'' property:
        
    {0}:
    - TASK_ONE
    - TASK_TWO
    
' -f $Name)
        return
    }

    $taskIdx = -1
    if( $config[$Name] -is [string] )
    {
        Write-Warning -Message ('It looks like pipeline ''{0}'' doesn''t have any tasks.' -f $Context.ConfigurationPath)
        $config[$Name] = @()
    }

    $knownTasks = Get-WhiskeyTasks
    foreach( $taskItem in $config[$Name] )
    {
        $taskIdx++
        if( $taskItem -is [string] )
        {
            $taskName = $taskItem
            $taskItem = @{ }
        }
        elseif( $taskItem -is [hashtable] )
        {
            $taskName = $taskItem.Keys | Select-Object -First 1
            $taskItem = $taskItem[$taskName]
            if( -not $taskItem )
            {
                $taskItem = @{ }
            }
        }
        else
        {
            continue
        }

        $Context.TaskName = $taskName
        $Context.TaskIndex = $taskIdx

        $errorPrefix = '{0}: {1}[{2}]: {3}: ' -f $Context.ConfigurationPath,$Name,$taskIdx,$taskName

        $errors = @()
        $pathIdx = -1


        if( -not $knownTasks.Contains($taskName) )
        {
            #I'm guessing we no longer need this code because we are going to be supporting a wider variety of tasks. Thus perhaps a different message will be necessary here.
            $knownTasks = $knownTasks.Keys | Sort-Object
            throw ('{0}: {1}[{2}]: ''{3}'' task does not exist. Supported tasks are:{4} * {5}' -f $Context.ConfigurationPath,$Name,$taskIdx,$taskName,[Environment]::NewLine,($knownTasks -join ('{0} * ' -f [Environment]::NewLine)))
        }

        $taskFunctionName = $knownTasks[$taskName]

        $optionalParams = @{ }
        if ( $Clean )
        {
            $optionalParams['Clean'] = $True
        }

        function Invoke-Event
        {
            param(
                $Prefix,
                $EventName
            )

            if( -not $events.ContainsKey($EventName) )
            {
                return
            }

            foreach( $commandName in $events[$EventName] )
            {
                Write-Verbose -Message $prefix
                Write-Verbose -Message ('{0}  [On{1}]  {2}' -f $prefix,$EventName,$commandName)
                $startedAt = Get-Date
                & $commandName -TaskContext $Context -TaskName $taskName -TaskParameter $taskItem @optionalParams 
                $endedAt = Get-Date
                $duration = $endedAt - $startedAt
                Write-Verbose ('{0}  {1}  COMPLETED in {2}' -f $prefix,(' ' * ($EventName.Length + 4)),$duration)
            }
        }

        #I feel like this is missing a piece, because the current way that Whiskey tasks are named, they will never be run by this logic.
        $prefix = '[{0}]' -f $taskName
        Invoke-Event -EventName 'BeforeTask' -Prefix $prefix
        Invoke-Event -EventName ('Before{0}Task' -f $taskName) -Prefix $prefix

        Write-Verbose -Message $prefix
        $startedAt = Get-Date
        & $taskFunctionName -TaskContext $context -TaskParameter $taskItem @optionalParams
        $endedAt = Get-Date
        $duration = $endedAt - $startedAt
        Write-Verbose ('{0}  COMPLETED in {1}' -f $prefix,$duration)

        Invoke-Event -Prefix $prefix -EventName 'AfterTask'
        Invoke-Event -Prefix $prefix -EventName ('After{0}Task' -f $taskName)
        Write-Verbose ($prefix)
        Write-Verbose ''
    }
}