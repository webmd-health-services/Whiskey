
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

    $knownTasks = Get-WhiskeyTask -Force

    $task = $knownTasks | Where-Object { $_.Name -eq $Name }

    if( -not $task )
    {
        $task = $knownTasks | Where-Object { $_.Aliases -contains $Name }
        $taskCount = ($task | Measure-Object).Count
        if( $taskCount -gt 1 )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Found {0} tasks with alias "{1}". Please update to use one of these task names: {2}.' -f $taskCount,$Name,(($task | Select-Object -ExpandProperty 'Name') -join ', '))
            return
        }
        if( $task -and $task.WarnWhenUsingAlias )
        {
            Write-WhiskeyWarning -Context $TaskContext -Message ('Task "{0}" is an alias to task "{1}". Please update "{2}" to use the task''s actual name, "{1}", instead of the alias.' -f $Name,$task.Name,$TaskContext.ConfigurationPath)
        }
    }

    if( -not $task )
    {
        $knownTaskNames = $knownTasks | Select-Object -ExpandProperty 'Name' | Sort-Object
        throw ('{0}: {1}[{2}]: ''{3}'' task does not exist. Supported tasks are:{4} * {5}' -f $TaskContext.ConfigurationPath,$Name,$TaskContext.TaskIndex,$Name,[Environment]::NewLine,($knownTaskNames -join ('{0} * ' -f [Environment]::NewLine)))
    }

    $taskCount = ($task | Measure-Object).Count
    if( $taskCount -gt 1 )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Found {0} tasks named "{1}". We don''t know which one to use. Please make sure task names are unique.' -f $taskCount,$Name)
        return
    }

    if( $task.Obsolete )
    {
        $message = 'The "{0}" task is obsolete and shouldn''t be used.' -f $Name
        if( $task.ObsoleteMessage )
        {
            $message = $task.ObsoleteMessage
        }
        Write-WhiskeyWarning -Context $TaskContext -Message $message
    }

    if( -not $task.Platform.HasFlag($CurrentPlatform) )
    {
        $msg = 'Unable to run task "{0}": it is only supported on the {1} platform(s) and we''re currently running on {2}.' -f `
                    $Name,$task.Platform,$CurrentPlatform
        Write-WhiskeyError -Message $msg -ErrorAction Stop
        return
    }

    if( $TaskContext.TaskDefaults.ContainsKey( $Name ) )
    {
        Merge-Parameter -SourceParameter $TaskContext.TaskDefaults[$Name] -TargetParameter $Parameter
    }

    Resolve-WhiskeyVariable -Context $TaskContext -InputObject $Parameter | Out-Null

    [hashtable]$taskProperties = $Parameter.Clone()
    $commonProperties = @{}
    foreach( $commonPropertyName in @(
        'OnlyBy',           'ExceptBy',
        'OnlyOnBranch',     'ExceptOnBranch',
        'OnlyDuring',       'ExceptDuring',
        'OnlyOnPlatform',   'ExceptOnPlatform',
        'IfExists',         'UnlessExists',
        'WorkingDirectory', 'OutVariable' ) )
    {
        if ($taskProperties.ContainsKey($commonPropertyName))
        {
            $commonProperties[$commonPropertyName] = $taskProperties[$commonPropertyName]
            $taskProperties.Remove($commonPropertyName)
        }
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
            if( $Parameter['WorkingDirectory'] )
            {
                # We need a full path because we pass it to `IO.Path.SetCurrentDirectory`.
                $workingDirectory =
                    $Parameter['WorkingDirectory'] |
                    Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory' -Mandatory -OnlySinglePath -PathType 'Directory' |
                    Resolve-Path |
                    Select-Object -ExpandProperty 'ProviderPath'
            }
            Set-Location -Path $workingDirectory
            [IO.Directory]::SetCurrentDirectory($workingDirectory)

            Invoke-Event -EventName 'BeforeTask' -Property $taskProperties
            Invoke-Event -EventName ('Before{0}Task' -f $Name) -Property $taskProperties

            Write-WhiskeyVerbose -Context $TaskContext -Message ''
            $TaskContext.StartTask($Name)
            Write-WhiskeyInfo -Context $TaskContext -Message "$($Name)" -NoIndent
            $taskTempDirectory = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('Temp.{0}.{1}' -f $Name,[IO.Path]::GetRandomFileName())
            $TaskContext.Temp = $taskTempDirectory
            if( -not (Test-Path -Path $TaskContext.Temp -PathType Container) )
            {
                New-Item -Path $TaskContext.Temp -ItemType 'Directory' -Force | Out-Null
            }

            $taskArgs = Get-TaskArgument -Name $task.CommandName -Property $taskProperties -Context $TaskContext

            # PowerShell's default DebugPreference when someone uses the -Debug switch is `Inquire`. That would cause a
            # build to hang, so let's set it to Continue so users can see debug output.
            if( $taskArgs['Debug'] )
            {
                $DebugPreference = 'Continue'
                $taskArgs.Remove('Debug')
            }

            $outVariable = $commonProperties['OutVariable']

            if ($outVariable)
            {
                $taskOutput = & $task.CommandName @taskArgs

                if (-not $taskOutput)
                {
                    $taskOutput = ''
                }

                Add-WhiskeyVariable -Context $TaskContext -Name $outVariable -Value $taskOutput
            }
            else
            {
                & $task.CommandName @taskArgs
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
