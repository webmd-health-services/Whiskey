
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
        [Whiskey.Context]
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
            $EventName,
            $Property
        )

        if( -not $events.ContainsKey($EventName) )
        {
            return
        }

        foreach( $commandName in $events[$EventName] )
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ''
            Write-WhiskeyVerbose -Context $TaskContext -Message ('[On{0}]  {1}' -f $EventName,$commandName)
            $startedAt = Get-Date
            $result = 'FAILED'
            try
            {
                $TaskContext.Temp = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('Temp.{0}.On{1}.{2}' -f $Name,$EventName,[IO.Path]::GetRandomFileName())
                if( -not (Test-Path -Path $TaskContext.Temp -PathType Container) )
                {
                    New-Item -Path $TaskContext.Temp -ItemType 'Directory' -Force | Out-Null
                }
                & $commandName -TaskContext $TaskContext -TaskName $Name -TaskParameter $Property
                $result = 'COMPLETED'
            }
            finally
            {
                Remove-WhiskeyFileSystemItem -Path $TaskContext.Temp
                $endedAt = Get-Date
                $duration = $endedAt - $startedAt
                Write-WhiskeyVerbose -Context $TaskContext ('{0}  {1} in {2}' -f (' ' * ($EventName.Length + 4)),$result,$duration)
            }
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
                if( ($targetValue | Get-Member -Name 'Keys') -and ($sourceValue | Get-Member -Name 'Keys') )
                {
                    Merge-Parameter -SourceParameter $sourceValue -TargetParameter $targetValue
                }
                continue
            }

            $TargetParameter[$key] = $sourceValue
        }
    }

    function Get-RequiredTool
    {
        param(
            $CommandName
        )

        $cmd = Get-Command -Name $CommandName -ErrorAction Ignore
        if( -not $cmd -or -not (Get-Member -InputObject $cmd -Name 'ScriptBlock') )
        {
            return
        }

        $cmd.ScriptBlock.Attributes | 
            Where-Object { $_ -is [Whiskey.RequiresToolAttribute] }
    }
    
    $TaskContext.TaskName = $Name

    if( $TaskContext.TaskDefaults.ContainsKey( $Name ) )
    {
        Merge-Parameter -SourceParameter $TaskContext.TaskDefaults[$Name] -TargetParameter $Parameter
    }

    Resolve-WhiskeyVariable -Context $TaskContext -InputObject $Parameter | Out-Null

    $taskProperties = $Parameter.Clone()
    foreach( $commonPropertyName in @( 'OnlyBy', 'ExceptBy', 'OnlyOnBranch', 'ExceptOnBranch', 'OnlyDuring', 'ExceptDuring', 'WorkingDirectory' ) )
    {
        $taskProperties.Remove($commonPropertyName)
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
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  OnlyBy: {2}; ByBuildServer: {1}' -f $onlyBy,$TaskContext.ByBuildServer)
                    return
                }
            }
            'BuildServer'
            {
                if( -not $TaskContext.ByBuildServer )
                {
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  OnlyBy: {0}; ByDeveloper: {1}' -f $onlyBy,$TaskContext.ByDeveloper)
                    return
                }
            }
            default
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''OnlyBy'' has an invalid value: ''{0}''. Valid values are ''Developer'' (to only run the task when the build is being run by a developer) or ''BuildServer'' (to only run the task when the build is being run by a build server).' -f $onlyBy)
            }
        }
    }
    
    $branch = $TaskContext.BuildMetadata.ScmBranch
    $executeTaskOnBranch = $true
    
    if( $Parameter['OnlyOnBranch'] -and $Parameter['ExceptOnBranch'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('This task defines both OnlyOnBranch and ExceptOnBranch properties. Only one of these can be used. Please remove one or both of these properties and re-run your build.')
    }
    
    if( $Parameter['OnlyOnBranch'] )
    {
        $executeTaskOnBranch =$false
        Write-WhiskeyVerbose -Context $TaskContext -Message ('OnlyOnBranch')
        foreach( $wildcard in $Parameter['OnlyOnBranch'] )
        {
            if( $branch -like $wildcard )
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('               {0}     -like  {1}' -f $branch, $wildcard)
                $executeTaskOnBranch = $true
                break
            }
            else
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('               {0}  -notlike  {1}' -f $branch, $wildcard)
            }
        }
    }

    if( $Parameter['ExceptOnBranch'] )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('ExceptOnBranch')
        foreach( $wildcard in $Parameter['ExceptOnBranch'] )
        {
            if( $branch -like $wildcard )
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('               {0}     -like  {1}' -f $branch, $wildcard)
                $executeTaskOnBranch = $false
                break
            }
            else
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('               {0}  -notlike  {1}' -f $branch, $wildcard)
            }
        }
    }
    
    if( -not $executeTaskOnBranch )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  {0} not configured to execute this task.' -f $branch)
        return
    }

    $workingDirectory = $TaskContext.BuildRoot
    if( $Parameter['WorkingDirectory'] )
    {
        $workingDirectory = $Parameter['WorkingDirectory'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory'
    }

    $requiredTools = Get-RequiredTool -CommandName $task.CommandName
    $startedAt = Get-Date
    $result = 'SKIPPED'
    Push-Location -Path $workingDirectory
    try
    {
        $modes = @( 'Clean', 'Initialize', 'Build' )
        $onlyDuring = $Parameter['OnlyDuring']
        $exceptDuring = $Parameter['ExceptDuring']

        if ($onlyDuring -and $exceptDuring)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Both ''OnlyDuring'' and ''ExceptDuring'' properties are used. These properties are mutually exclusive, i.e. you may only specify one or the other.'
        }
        elseif ($onlyDuring -and ($onlyDuring -notin $modes))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''OnlyDuring'' has an invalid value: ''{0}''. Valid values are: ''{1}''.' -f $onlyDuring,($modes -join "', '"))
        }
        elseif ($exceptDuring -and ($exceptDuring -notin $modes))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ExceptDuring'' has an invalid value: ''{0}''. Valid values are: ''{1}''.' -f $exceptDuring,($modes -join "', '"))
        }

        if ($onlyDuring -and ($TaskContext.RunMode -ne $onlyDuring))
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  OnlyDuring: {0} -- Current RunMode: {1}' -f $onlyDuring,$TaskContext.RunMode)
            return
        }
        elseif ($exceptDuring -and ($TaskContext.RunMode -eq $exceptDuring))
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  ExceptDuring: {0} -- Current RunMode: {1}' -f $exceptDuring,$TaskContext.RunMode)
            return
        }
    
        $inCleanMode = $TaskContext.ShouldClean
        if( $inCleanMode )
        {
            if( -not $task.SupportsClean )
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  SupportsClean: $false')
                return
            }
        }

        foreach( $requiredTool in $requiredTools )
        {
            Install-WhiskeyTool -ToolInfo $requiredTool `
                                -InstallRoot $TaskContext.BuildRoot `
                                -TaskParameter $taskProperties `
                                -InCleanMode:$inCleanMode `
                                -ErrorAction Stop
        }

        if( $TaskContext.ShouldInitialize -and -not $task.SupportsInitialize )
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('SKIPPED  SupportsInitialize: $false')
            return
        }

        Invoke-Event -EventName 'BeforeTask' -Property $taskProperties
        Invoke-Event -EventName ('Before{0}Task' -f $Name) -Property $taskProperties

        Write-WhiskeyVerbose -Context $TaskContext -Message ''
        $result = 'FAILED'
        $startedAt = Get-Date
        $TaskContext.Temp = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('Temp.{0}.{1}' -f $Name,[IO.Path]::GetRandomFileName())
        if( -not (Test-Path -Path $TaskContext.Temp -PathType Container) )
        {
            New-Item -Path $TaskContext.Temp -ItemType 'Directory' -Force | Out-Null
        }
        & $task.CommandName -TaskContext $TaskContext -TaskParameter $taskProperties
        $result = 'COMPLETED'
    }
    finally
    {
        # Clean required tools *after* running the task since the task might need a required tool in order to do the cleaning (e.g. using Node to clean up installed modules)
        if( $TaskContext.ShouldClean )
        {
            foreach( $requiredTool in $requiredTools )
            {
                Uninstall-WhiskeyTool -InstallRoot $TaskContext.BuildRoot -Name $requiredTool.Name
            }
        }

        if( $TaskContext.Temp -and (Test-Path -Path $TaskContext.Temp -PathType Container) )
        {
            Remove-Item -Path $TaskContext.Temp -Recurse -Force -ErrorAction Ignore
        }
        $endedAt = Get-Date
        $duration = $endedAt - $startedAt
        Write-WhiskeyVerbose -Context $TaskContext -Message ('{0} in {1}' -f $result,$duration)
        Pop-Location
    }

    Invoke-Event -EventName 'AfterTask' -Property $taskProperties
    Invoke-Event -EventName ('After{0}Task' -f $Name) -Property $taskProperties
    Write-WhiskeyVerbose -Context $TaskContext -Message ''
}