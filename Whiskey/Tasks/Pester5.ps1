
function Invoke-WhiskeyPester5Task
{
    [Whiskey.Task('Pester5')]
    [Whiskey.RequiresPowerShellModule('Pester',ModuleInfoParameterName='PesterModuleInfo',Version='5.*',VersionParameterName='Version',SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Alias('Path')]
        [object]$Script,

        [String[]]$Exclude,

        [int]$DescribeDurationReportCount = 0,

        [int]$ItDurationReportCount = 0,

        [Management.Automation.PSModuleInfo]$PesterModuleInfo,

        [Object]$Argument = @{},

        [switch]$NoJob
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $Exclude )
    {
        $Exclude = $Exclude | Convert-WhiskeyPathDirectorySeparator 
    }

    if( -not $Script )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Script' -Message ('Script is mandatory.')
        return
    }

    $Script = & {
        foreach( $scriptItem in $Script )
        {
            $path = $null

            if( $scriptItem -is [String] )
            {
                $path = $scriptItem
            }
            elseif( $scriptItem | Get-Member -Name 'Keys' )
            {
                $path = $scriptItem['Path']
                $numPaths = ($path | Measure-Object).Count
                if( $numPaths -gt 1 )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Script' -Message ('when passing a hashtable to Pester''s "Script" parameter, the "Path" value must be a single string. We got {0} strings: {1}' -f $numPaths,($path -join ', '))
                    continue
                }
            }

            $path = Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Script' -Path $path -Mandatory

            foreach( $pathItem in $path )
            {
                if( $Exclude )
                {
                    $excluded = $false
                    foreach( $exclusion in $Exclude )
                    {
                        if( $pathItem -like $exclusion )
                        {
                            Write-WhiskeyVerbose -Context $TaskContext -Message ('EXCLUDE  {0} -like    {1}' -f $pathItem,$exclusion)
                            $excluded = $true
                        }
                        else
                        {
                            Write-WhiskeyVerbose -Context $TaskContext -Message ('         {0} -notlike {1}' -f $pathItem,$exclusion)
                        }
                    }

                    if( $excluded )
                    {
                        continue
                    }
                }

                if( $scriptItem -is [String] )
                {
                    Write-Output $pathItem
                    continue
                }

                if( $scriptItem | Get-Member -Name 'Keys' )
                {
                    $newScriptItem = $scriptItem.Clone()
                    $newScriptItem['Path'] = $pathItem
                    Write-Output $newScriptItem
                }
            }
        }
    }

    if( -not $Script )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Found no tests to run.')
        return
    }

    $pesterManifestPath = $PesterModuleInfo.Path

    $Argument['Path'] = $Script
    $Argument['PassThru'] = $true

    if( $Argument.ContainsKey('Output') )
    {
        $outputFile = $Argument['Output']
    }
    else
    {
        $outputFileRoot = Resolve-Path -Path $TaskContext.OutputDirectory -Relative
        $outputFile = Join-Path -Path $outputFileRoot -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
        $Argument['Output'] = $outputFile
    }

    $Argument | Write-WhiskeyObject -Context $context -Level Verbose

    $args = @(
        (Get-Location).Path,
        $pesterManifestPath,
        $Argument,
        @{
            'VerbosePreference' = $VerbosePreference;
            'DebugPreference' = $DebugPreference;
            'ProgressPreference' = $ProgressPreference;
            'WarningPreference' = $WarningPreference;
            'ErrorActionPreference' = $ErrorActionPreference;
        }
    )

    $cmdName = 'Start-Job'
    if( $NoJob )
    {
        $cmdName = 'Invoke-Command'
    }

    $config = [PesterConfiguration]::Default
    $config.TestResult.Enabled = $true
    $config.Run.Path = $Argument.Path
    $config.Run.PassThru = $true
    $config.Run.Throw = $true
    # $config.Should.ErrorAction.Value = $ErrorActionPreference
    $config.Debug.ShowFullErrors = $true
    $config.Debug.WriteDebugMessages = $true

    $configuration = [PesterConfiguration]@{
        Debug = @{
            ShowFullErrors = $true
            WriteDebugMessages = $true;
        }
        Run = @{
            Path = $Argument.Path
            PassThru = $true
            Throw = $true
        }
        Should = @{
            ErrorAction = $ErrorActionPreference
        }
        TestResult = @{
            Enabled = $true;
            OutputPath = $outputFile
        }
    }

    try {
        # Set-Location -Path $WorkingDirectory
        # Import-Module -Name $pesterManifestPath -Verbose:$false -WarningAction Ignore
        $testResult = Invoke-Pester -Configuration $configuration
    }
    catch {
        Write-Error -ErrorRecord $_
    }

    # $result = & $cmdName -ArgumentList $args -ScriptBlock {
    #     param(
    #         [String]$WorkingDirectory,
    #         [String]$PesterManifestPath,
    #         [hashtable]$Parameter,
    #         [hashtable]$Preference
    #     )

    #     Set-Location -Path $WorkingDirectory

    #     $VerbosePreference = 'SilentlyContinue'
    #     Import-Module -Name $PesterManifestPath -Verbose:$false -WarningAction Ignore

    #     $VerbosePreference = $Preference['VerbosePreference']
    #     $DebugPreference = $Preference['DebugPreference']
    #     $ProgressPreference = $Preference['ProgressPreference']
    #     $WarningPreference = $Preference['WarningPreference']
    #     $ErrorActionPreference = $Preference['ErrorActionPreference']
        
    #     Invoke-Pester @Parameter
    # }
    
    # if( -not $NoJob )
    # {
    #     $testResult = $testResult | Receive-Job -Wait -AutoRemoveJob -InformationAction Ignore
    # }

    $testResult.Tests |
        Group-Object -Property 'Path' |
        ForEach-Object {
            $totalTime = [TimeSpan]::Zero
            $_.Group | ForEach-Object { $totalTime += $_.Duration }
            [pscustomobject]@{
                                Describe = $_.Name;
                                Duration = $totalTime
                            }
        } | Sort-Object -Property 'Duration' -Descending |
        Select-Object -First $DescribeDurationReportCount |
        Format-Table -AutoSize

    $testResult.Tests |
        Sort-Object -Property 'Duration' -Descending |
        Select-Object -First $ItDurationReportCount |
        Format-Table -AutoSize -Property 'Describe','Name','Duration'

    Publish-WhiskeyPesterTestResult -Path $outputFile

    $outputFileContent = Get-Content -Path $outputFile -Raw
    $outputFileContent | Write-WhiskeyDebug
    $result = [xml]$outputFileContent

    if( -not $result )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to parse Pester output XML report "{0}".' -f $outputFile)
        return
    }

    if( $result.DocumentElement.errors -ne '0' -or $result.DocumentElement.failures -ne '0' )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Pester tests failed.')
        return
    }
}
