
function Invoke-WhsCIBuild
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context for the build. Use `New-WhsCIContext` to create context objects.
        $Context,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Set-WhsCIBuildStatus -Context $Context -Status Started

    $succeeded = $false
    Push-Location -Path $Context.BuildRoot
    try
    {
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve

        Write-Verbose -Message ('Building version {0}' -f $Context.Version.SemVer2)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer2NoBuildMetadata)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.Version)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer1)

        $config = $Context.Configuration

        if( $config.ContainsKey('BuildTasks') )
        {
            # Tasks that should be called with the WhatIf switch when run by developers
            # This makes builds go a little faster.
            $developerWhatIfTasks = @{
                                        'ProGetUniversalPackage' = $true;
                                     }

            $taskIdx = -1
            if( $config['BuildTasks'] -is [string] )
            {
                Write-Warning -Message ('It looks like ''{0}'' doesn''t define any build tasks.' -f $Context.ConfigurationPath)
                $config['BuildTasks'] = @()
            }

            $knownTasks = Get-WhiskeyTasks
            foreach( $task in $config['BuildTasks'] )
            {
                $taskIdx++
                if( $task -is [string] )
                {
                    $taskName = $task
                    $task = @{ }
                }
                elseif( $task -is [hashtable] )
                {
                    $taskName = $task.Keys | Select-Object -First 1
                    $task = $task[$taskName]
                    if( -not $task )
                    {
                        $task = @{ }
                    }
                }
                else
                {
                    continue
                }

                $Context.TaskName = $taskName
                $Context.TaskIndex = $taskIdx

                $errorPrefix = '{0}: BuildTasks[{1}]: {2}: ' -f $Context.ConfigurationPath,$taskIdx,$taskName

                $errors = @()
                $pathIdx = -1


                if( -not $knownTasks.Contains($taskName) )
                {
                    #I'm guessing we no longer need this code because we are going to be supporting a wider variety of tasks. Thus perhaps a different message will be necessary here.
                    $knownTasks = $knownTasks.Keys | Sort-Object
                    throw ('{0}: BuildTasks[{1}]: ''{2}'' task does not exist. Supported tasks are:{3} * {4}' -f $Context.ConfigurationPath,$taskIdx,$taskName,[Environment]::NewLine,($knownTasks -join ('{0} * ' -f [Environment]::NewLine)))
                }

                $taskFunctionName = $knownTasks[$taskName]

                $optionalParams = @{ }
                if( $Context.ByDeveloper -and $developerWhatIfTasks.ContainsKey($taskName) )
                {
                    $optionalParams['WhatIf'] = $True
                }
                if ( $Clean )
                {
                    $optionalParams['Clean'] = $True
                }

                Write-Verbose -Message ('{0}' -f $taskName)
                $startedAt = Get-Date
                #I feel like this is missing a piece, because the current way that WhsCI tasks are named, they will never be run by this logic.
                & $taskFunctionName -TaskContext $context -TaskParameter $task @optionalParams
                $endedAt = Get-Date
                $duration = $endedAt - $startedAt
                Write-Verbose ('{0} COMPLETED in {1}' -f $taskName,$duration)
                Write-Verbose ('')

            }
            New-WhsCIBuildMasterPackage -TaskContext $Context
        }

        $succeeded = $true
    }
    finally
    {
        if( $Clean )
        {
            Remove-Item -path $Context.OutputDirectory -Recurse -Force | Out-String | Write-Verbose
        }
        Pop-Location

        $status = 'Failed'
        if( $succeeded )
        {
            $status = 'Completed'
        }
        Set-WhsCIBuildStatus -Context $Context -Status $status

        if( $Context.ByBuildServer -and $succeeded )
        {
            Publish-WhsCITag -TaskContext $Context 
        }

    }
}
