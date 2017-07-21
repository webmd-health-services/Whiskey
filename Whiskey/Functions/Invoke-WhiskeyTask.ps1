
function Invoke-WhiskeyTask
{
    <#
    .SYNOPSIS
    Runs a Whiskey task.
    
    .DESCRIPTION
    The `Invoke-WhiskeyTask` function runs a Whiskey task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of the task.
        $Name,
        
        [Parameter(Mandatory=$true)]
        [hashtable]
        # The parameters/configuration to use to run the task. 
        $Parameter,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'

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
            & $commandName -TaskContext $TaskContext -TaskName $Name -TaskParameter $Parameter @optionalParams 
            $endedAt = Get-Date
            $duration = $endedAt - $startedAt
            Write-Verbose ('{0}  {1}  COMPLETED in {2}' -f $prefix,(' ' * ($EventName.Length + 4)),$duration)
        }
    }

    $optionalParams = @{ }
    if( $Clean )
    {
        $optionalParams['Clean'] = $true
    }

    $knownTasks = Get-WhiskeyTasks

    $errorPrefix = '{0}: {1}[{2}]: {3}: ' -f $TaskContext.ConfigurationPath,$TaskContext.PipelineName,$TaskContext.TaskIndex,$Name

    if( -not $knownTasks.Contains($Name) )
    {
        #I'm guessing we no longer need this code because we are going to be supporting a wider variety of tasks. Thus perhaps a different message will be necessary here.
        $knownTasks = $knownTasks.Keys | Sort-Object
        throw ('{0}: {1}[{2}]: ''{3}'' task does not exist. Supported tasks are:{4} * {5}' -f $TaskContext.ConfigurationPath,$Name,$TaskContext.TaskIndex,$Name,[Environment]::NewLine,($knownTasks -join ('{0} * ' -f [Environment]::NewLine)))
    }

    function Merge-Parameter
    {
        param(
            [hashtable]
            $SourceParameter,

            [hashtable]
            $TargetParameter
        )

        foreach( $key in $SourceParameter.Keys )
        {
            $sourceValue = $SourceParameter[$key]
            if( $TargetParameter.ContainsKey($key) )
            {
                $targetValue = $TargetParameter[$key]
                if( $targetValue -is [hashtable] -and $sourceValue -is [hashtable] )
                {
                    Merge-Parameter -SourceParameter $sourceValue -TargetParameter $targetValue
                }
                continue
            }

            $TargetParameter[$key] = $sourceValue
        }
    }

    $TaskContext.TaskName = $Name

    if( $TaskContext.TaskDefaults.ContainsKey( $Name ) )
    {
        Merge-Parameter -SourceParameter $TaskContext.TaskDefaults[$Name] -TargetParameter $Parameter
    }

    #I feel like this is missing a piece, because the current way that Whiskey tasks are named, they will never be run by this logic.
    $prefix = '[{0}]' -f $Name
    Invoke-Event -EventName 'BeforeTask' -Prefix $prefix
    Invoke-Event -EventName ('Before{0}Task' -f $Name) -Prefix $prefix

    Write-Verbose -Message $prefix
    $startedAt = Get-Date
    $taskFunctionName = $knownTasks[$Name]
    & $taskFunctionName -TaskContext $TaskContext -TaskParameter $Parameter @optionalParams
    $endedAt = Get-Date
    $duration = $endedAt - $startedAt
    Write-Verbose ('{0}  COMPLETED in {1}' -f $prefix,$duration)

    Invoke-Event -Prefix $prefix -EventName 'AfterTask'
    Invoke-Event -Prefix $prefix -EventName ('After{0}Task' -f $Name)
    Write-Verbose ($prefix)
    Write-Verbose ''
}