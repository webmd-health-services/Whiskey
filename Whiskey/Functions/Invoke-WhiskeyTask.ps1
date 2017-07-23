
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
        $Parameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

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
            & $commandName -TaskContext $TaskContext -TaskName $Name -TaskParameter $Parameter
            $endedAt = Get-Date
            $duration = $endedAt - $startedAt
            Write-Verbose ('{0}  {1}  COMPLETED in {2}' -f $prefix,(' ' * ($EventName.Length + 4)),$duration)
        }
    }

    $knownTasks = Get-WhiskeyTask

    $task = $knownTasks | Where-Object { $_.Name -eq $Name }

    $errorPrefix = '{0}: {1}[{2}]: {3}: ' -f $TaskContext.ConfigurationPath,$TaskContext.PipelineName,$TaskContext.TaskIndex,$Name

    if( -not $task )
    {
        $knownTaskNames = $knownTasks | Select-Object -ExpandProperty 'Name' | Sort-Object
        throw ('{0}: {1}[{2}]: ''{3}'' task does not exist. Supported tasks are:{4} * {5}' -f $TaskContext.ConfigurationPath,$Name,$TaskContext.TaskIndex,$Name,[Environment]::NewLine,($knownTaskNames -join ('{0} * ' -f [Environment]::NewLine)))
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
    
    if( $TaskContext.ShouldClean() -and -not $task.SupportsClean )
    {
        Write-Verbose -Message ('{0}  SKIPPED  SupportsClean: $false' -f $prefix)
        return
    }
    if( $TaskContext.ShouldInitialize() -and -not $task.SupportsInitialize )
    {
        Write-Verbose -Message ('{0}  SKIPPED  SupportsInitialize: $false' -f $prefix)
        return
    }

    $onlyBy = $Parameter['OnlyBy']
    if( $onlyBy )
    {
        switch( $onlyBy )
        {
            'Developer'
            {
                if( -not $TaskContext.ByDeveloper )
                {
                    Write-Verbose -Message ('{0}  SKIPPED  OnlyBy: {1}; ByBuildServer: {2}' -f $prefix,$onlyBy,$TaskContext.ByBuildServer)
                    return
                }
            }
            'BuildServer'
            {
                if( -not $TaskContext.ByBuildServer )
                {
                    Write-Verbose -Message ('{0}  SKIPPED  OnlyBy: {1}; ByDeveloper: {2}' -f $prefix,$onlyBy,$TaskContext.ByDeveloper)
                    return
                }
            }
            default
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''OnlyBy'' has an invalid value: ''{0}''. Valid values are ''Developer'' (to only run the task when the build is being run by a developer) or ''BuildServer'' (to only run the task when the build is being run by a build server).' -f $onlyBy)
            }
        }
    }

    Invoke-Event -EventName 'BeforeTask' -Prefix $prefix
    Invoke-Event -EventName ('Before{0}Task' -f $Name) -Prefix $prefix

    Write-Verbose -Message $prefix
    $startedAt = Get-Date
    & $task.CommandName -TaskContext $TaskContext -TaskParameter $Parameter
    $endedAt = Get-Date
    $duration = $endedAt - $startedAt
    Write-Verbose ('{0}  COMPLETED in {1}' -f $prefix,$duration)

    Invoke-Event -Prefix $prefix -EventName 'AfterTask'
    Invoke-Event -Prefix $prefix -EventName ('After{0}Task' -f $Name)
    Write-Verbose ($prefix)
    Write-Verbose ''
}