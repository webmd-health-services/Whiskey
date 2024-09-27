
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
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        # The name of the task.
        [Parameter(Mandatory)]
        [String] $Name,

        # The parameters/configuration to use to run the task.
        [Parameter(Mandatory)]
        [hashtable] $Parameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Invoke-Event
    {
        param(
            $EventName,
            $Property
        )

        $events = $TaskContext.Events

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
                Write-WhiskeyVerbose -Context $TaskContext -Message ''
            }
        }
    }

    function Merge-Parameter
    {
        param(
            [hashtable]$SourceParameter,

            [hashtable]$TargetParameter
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

    $whiskeyYmlPath = $TaskContext.ConfigurationPath | Resolve-WhiskeyRelativePath
    $whiskeyYmlDisplayPath = $whiskeyYmlPath | Format-Path

    $knownTasks = Get-WhiskeyTask -Force

    $task = $null
    $taskNames = @($Name, ($Name -replace '_'))

    foreach ($taskName in $taskNames)
    {
        $task = $knownTasks | Where-Object 'Name' -EQ $taskName

        if (-not $task)
        {
            $task = $knownTasks | Where-Object 'Aliases' -contains $taskName
            $taskCount = ($task | Measure-Object).Count
            if ($taskCount -gt 1)
            {
                $actualTaskNames = ($task | Select-Object -ExpandProperty 'Name') -join ', '
                $msg = "Found ${taskCount} tasks with alias ""${taskName}"". Please update to use one of these task " +
                       "names instead: ${actualTaskNames}."
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                return
            }
            if( $task -and $task.WarnWhenUsingAlias )
            {
                $msg = "Task ""${Name}"" is an alias to task ""$($task.Name)"". Please update " +
                       "${whiskeyYmlDisplayPath} to use the task''s actual name, ""$($task.Name)"", instead of the " +
                       'alias.'
                Write-WhiskeyWarning -Context $TaskContext -Message $msg
            }
        }
    }

    if (-not $task -and ($Parameter.Count -eq 0 -or $Parameter.ContainsKey('')))
    {
        # By default, assume task is an executable command.
        $task = $knownTasks | Where-Object 'Name' -eq 'Exec'
        $Parameter[''] = $Name
    }

    if (-not $task)
    {
        $knownTaskNames = $knownTasks | Select-Object -ExpandProperty 'Name' | Sort-Object
        $msg = "${whiskeyYmlDisplayPath}: ${Name}[$($TaskContext.TaskIndex)]: ""${Name}"" task does not exist. " +
               "Supported tasks are:$([Environment]::NewLine) " +
               "$($knownTaskNames -join "$([Environment]::NewLine) * ")"
        throw $msg
    }

    # Use the official task name.
    $Name = $task.Name

    $taskCount = ($task | Measure-Object).Count
    if( $taskCount -gt 1 )
    {
        $msg = "Found ${taskCount} tasks named ""${Name}"". We don't know which one to use. Please make sure task " +
               'names are unique.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if( $task.Obsolete )
    {
        $message = "The ""${Name}"" task is obsolete and shouldn''t be used."
        if( $task.ObsoleteMessage )
        {
            $message = $task.ObsoleteMessage
        }
        Write-WhiskeyWarning -Context $TaskContext -Message $message
    }

    if( -not $task.Platform.HasFlag($script:currentPlatform) )
    {
        $msg = "Unable to run task ""${Name}"" because it is only supported on the $($task.Platform) platform(s) and " +
               "we're currently running on ${script:currentPlatform}."
        Write-WhiskeyError -Message $msg -ErrorAction Stop
        return
    }

    foreach ($taskName in $taskNames)
    {
        if ($TaskContext.TaskDefaults.ContainsKey($taskName))
        {
            Merge-Parameter -SourceParameter $TaskContext.TaskDefaults[$taskName] -TargetParameter $Parameter
        }
    }

    Resolve-WhiskeyVariable -Context $TaskContext -InputObject $Parameter | Out-Null

    $psCommonParameterNames = @(
        $script:debugPropertyName,
        $script:errorActionPropertyName,
        $script:informationActionPropertyName,
        $script:outVariablePropertyName,
        $script:verbosePropertyName,
        $script:warningActionPropertyName
    )

    $whiskeyCommonPropertyNames = $script:skipPropertyNames + @( $script:workingDirectoryPropertyName )

    $allCommonPropertyNames = $psCommonParameterNames + $whiskeyCommonPropertyNames

    $obsoleteCommonPropertyNames = @(
        'ErrorAction'
        'ExceptBy'
        'ExceptDuring'
        'ExceptOnBranch'
        'ExceptOnPlatform'
        'IfExists'
        'InformationAction'
        'OnlyBy'
        'OnlyDuring'
        'OnlyOnBranch'
        'OnlyOnPlatform'
        'OutVariable'
        'UnlessExists'
        'WarningAction'
        'WorkingDirectory'
    )

    # Normalize common property names. TODO: remove once ready to make this a backwards-incompatible change.
    foreach ($propertyName in $obsoleteCommonPropertyNames)
    {
        if (-not $Parameter.ContainsKey($propertyName))
        {
            $propertyName = ".${propertyName}"
            if (-not $Parameter.ContainsKey($propertyName))
            {
                continue
            }
        }

        $newPropertyName =
            $allCommonPropertyNames | Where-Object { ($_ -replace '[._]', '') -eq ($propertyName -replace '[._]') }

        $msg = "Built-in, common task property ${propertyName} renamed to ${newPropertyName}. Please rename the " +
               "${Name} task's ${propertyName} property to ${newPropertyName} in ${whiskeyYmlDisplayPath}."
        Write-WhiskeyWarning -Context $TaskContext -Message $msg

        $Parameter[$newPropertyName] = $Parameter[$propertyName]
        [void]$Parameter.Remove($propertyName)
    }

    # Only common properties are allowed to start with a period. Warn users if we find a non-common property that begins
    # with a period. TODO: make this an error when ready to make this a backwards-incompatible change.
    foreach ($propertyName in $Parameter.Keys)
    {
        if (-not $propertyName.StartsWith('.'))
        {
            continue
        }

        if ($allCommonPropertyNames -contains $propertyName)
        {
            continue
        }

        $msg = "Property ""${propertyName}"" on task ${Name} begins with a period character. Only Whiskey's " +
               'built-in, common task properties can begin with a period. Please remove the period character from ' +
               "the property's name in ${whiskeyYmlDisplayPath}."
        Write-WhiskeyWarning -Context $TaskContext -Message $msg
    }

    [hashtable]$taskProperties = $Parameter.Clone()

    $commonProperties = @{}
    foreach ($propertyName in $whiskeyCommonPropertyNames)
    {
        if (-not $taskProperties.ContainsKey($propertyName))
        {
            continue
        }

        $commonProperties[$propertyName] = $taskProperties[$propertyName]
        [void]$taskProperties.Remove($propertyName)
    }

    # Convert the common property names that are natively supported by PowerShell into their PowerShell names.
    $psPropToParamMap = @{
        $script:debugPropertyName = 'Debug'
        $script:errorActionPropertyName = 'ErrorAction'
        $script:informationActionPropertyName = 'InformationAction'
        $script:outVariablePropertyName = 'OutVariable'
        $script:verbosePropertyName = 'Verbose'
        $script:warningActionPropertyName = 'WarningAction'
    }
    foreach ($propertyName in $psCommonParameterNames)
    {
        if (-not $taskProperties.ContainsKey($propertyName))
        {
            continue
        }

        if (-not $psPropToParamMap.ContainsKey($propertyName))
        {
            $msg = "Failed to execute task ${Name} because we found a common property, ${propertyName}, that doesn't " +
                   'map to a known PowerShell common property. This is a Whiskey development problem.'
            Write-WhiskeyError -Message $TaskContext -Message $msg
            continue
        }

        $psParameterName = $psPropToParamMap[$propertyName]

        $taskProperties[$psParameterName] = $taskProperties[$propertyName]
        [void]$taskProperties.Remove($propertyName)
    }

    # Start every task in the BuildRoot.
    Push-Location $TaskContext.BuildRoot
    $originalDirectory = [IO.Directory]::GetCurrentDirectory()
    [IO.Directory]::SetCurrentDirectory($TaskContext.BuildRoot)
    try
    {
        if( Test-WhiskeyTaskSkip -Context $TaskContext -Properties $commonProperties)
        {
            $result = 'SKIPPED'
            return
        }

        $inCleanMode = $TaskContext.ShouldClean
        if( $inCleanMode )
        {
            if( -not $task.SupportsClean )
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('SupportsClean.{0} -ne Build.ShouldClean.{1}' -f $task.SupportsClean,$TaskContext.ShouldClean)
                $result = 'SKIPPED'
                return
            }
        }

        $requiredTools = Get-RequiredTool -CommandName $task.CommandName
        foreach( $requiredTool in $requiredTools )
        {
            Install-WhiskeyTool -ToolInfo $requiredTool `
                                -InstallRoot $TaskContext.BuildRoot.FullName `
                                -TaskParameter $taskProperties `
                                -OutFileRootPath $TaskContext.OutputDirectory.FullName `
                                -InCleanMode:$inCleanMode `
                                -ErrorAction Stop
        }

        if( $TaskContext.ShouldInitialize -and -not $task.SupportsInitialize )
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('SupportsInitialize.{0} -ne Build.ShouldInitialize.{1}' -f $task.SupportsInitialize,$TaskContext.ShouldInitialize)
            $result = 'SKIPPED'
            return
        }

        $taskTempDirectory = ''
        $result = 'FAILED'

        $originalDebugPreference = $DebugPreference
        try
        {
            $workingDirectory = $TaskContext.BuildRoot
            if( $Parameter[$script:workingDirectoryPropertyName] )
            {
                # We need a full path because we pass it to `IO.Path.SetCurrentDirectory`.
                $workingDirectory =
                    $Parameter[$script:workingDirectoryPropertyName] |
                    Resolve-WhiskeyTaskPath -TaskContext $TaskContext `
                                            -PropertyName $script:workingDirectoryPropertyName `
                                            -Mandatory `
                                            -OnlySinglePath `
                                            -PathType 'Directory' |
                    Resolve-Path |
                    Select-Object -ExpandProperty 'ProviderPath'
            }
            Set-Location -Path $workingDirectory
            [IO.Directory]::SetCurrentDirectory($workingDirectory)

            Invoke-Event -EventName 'BeforeTask' -Property $taskProperties
            Invoke-Event -EventName ('Before{0}Task' -f $Name) -Property $taskProperties

            Write-WhiskeyVerbose -Context $TaskContext -Message ''
            $TaskContext.StartTask($Name)
            if ($Name -ne 'Exec')
            {
                Write-WhiskeyInfo -Context $TaskContext -Message "$($Name)" -NoIndent
            }
            $taskTempDirectory = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('Temp.{0}.{1}' -f $Name,[IO.Path]::GetRandomFileName())
            $TaskContext.Temp = $taskTempDirectory
            if( -not (Test-Path -Path $TaskContext.Temp -PathType Container) )
            {
                New-Item -Path $TaskContext.Temp -ItemType 'Directory' -Force | Out-Null
            }

            $taskArgs = Get-TaskArgument -Task $task -Property $taskProperties -Context $TaskContext

            # PowerShell's default DebugPreference when someone uses the -Debug switch is `Inquire`. That would cause a
            # build to hang, so let's set it to Continue so users can see debug output.
            if ($taskArgs['Debug'])
            {
                $DebugPreference = 'Continue'
                $taskArgs.Remove('Debug')
            }

            $outVarName = $Parameter[$script:outVariablePropertyName]

            # If the task doesn't have the [CmdletBinding()] parameter, fake it with Tee-Object.
            if ($outVarName -and -not $taskArgs.ContainsKey('OutVariable'))
            {
                & $task.CommandName @taskArgs | Tee-Object -Variable $outVarName
            }
            else
            {
                & $task.CommandName @taskArgs
            }

            if ($outVarName)
            {
                Add-WhiskeyVariable -Context $TaskContext `
                                    -Name $outVarName `
                                    -Value (Get-Variable -Name $outVarName -ValueOnly)
            }
            $result = 'COMPLETED'
        }
        finally
        {
            $DebugPreference = $originalDebugPreference

            # Clean required tools *after* running the task since the task might need a required tool in order to do the cleaning (e.g. using Node to clean up installed modules)
            if( $TaskContext.ShouldClean )
            {
                foreach( $requiredTool in $requiredTools )
                {
                    Uninstall-WhiskeyTool -BuildRoot $TaskContext.BuildRoot -ToolInfo $requiredTool
                }
            }

            if( $taskTempDirectory -and (Test-Path -Path $taskTempDirectory -PathType Container) )
            {
                Remove-Item -Path $taskTempDirectory -Recurse -Force -ErrorAction Ignore
            }
            $Context.StopTask()
            $duration = $Context.TaskStopwatch.Elapsed
            if( $result -eq 'FAILED' )
            {
                $msg = "!$($taskWriteIndent.Substring(1))FAILED"
                Write-WhiskeyInfo -Context $TaskContext -Message $msg -NoIndent
            }
            Write-WhiskeyInfo -Context $TaskContext -Message '' -NoIndent
        }

        Invoke-Event -EventName 'AfterTask' -Property $taskProperties
        Invoke-Event -EventName ('After{0}Task' -f $Name) -Property $taskProperties
    }
    finally
    {
        [IO.Directory]::SetCurrentDirectory($originalDirectory)
        Pop-Location
    }
}
