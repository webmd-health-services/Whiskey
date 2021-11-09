
function Invoke-WhiskeyPester5Task
{
    [Whiskey.Task('Pester5')]
    [Whiskey.RequiresPowerShellModule('Pester',
                                      ModuleInfoParameterName='PesterModuleInfo', Version='5.*',
                                      VersionParameterName='Version', SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Alias('Path')]
        [object] $Script,

        [String[]] $Exclude,

        [int] $DescribeDurationReportCount = 0,

        [int] $ItDurationReportCount = 0,

        [Management.Automation.PSModuleInfo] $PesterModuleInfo,

        [Object] $Argument = @{},

        [switch] $NoJob
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

    if( -not $Argument.ContainsKey('OutputFormat') )
    {
        $Argument['OutputFormat'] = 'NUnitXml'
    }

    $testName = ''
    if($Argument.ContainsKey('TestName'))
    {
        $testName = $Argument.TestName
    }

    $Argument | Write-WhiskeyObject -Context $context -Level Verbose

    $data = $null
    # Checking to see if Script is a container with data being passed in for tests
    if($Script -is [System.Array] -and $Script[0] -is [Hashtable])
    {
        [String[]] $paths = @()
        $Script | ForEach-Object {
            $paths += ($_.Path)
        }
        $data = $Script[0].Data
        $Script = $paths
    }
    
    $cmdArgList = @(
        (Get-Location).Path,
        $pesterManifestPath,
        $Script,
        $data,
        $testName,
        $outputFile,
        $Argument.OutputFormat,
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

    $result = & $cmdName -ArgumentList $cmdArgList -ScriptBlock {
        param(
            [String] $WorkingDirectory,

            [String] $PesterManifestPath,

            [String[]] $Path,

            [hashtable] $TestData,

            [String] $TestName,

            [String] $OutputPath,

            [String] $OutputFormat,

            [hashtable] $Preference
        )
        
        Set-Location -Path $WorkingDirectory

        $VerbosePreference = 'SilentlyContinue'
        Import-Module -Name $PesterManifestPath -Verbose:$false -WarningAction Ignore

        $VerbosePreference = $Preference['VerbosePreference']
        $DebugPreference = $Preference['DebugPreference']
        $ProgressPreference = $Preference['ProgressPreference']
        $WarningPreference = $Preference['WarningPreference']
        $ErrorActionPreference = $Preference['ErrorActionPreference']

        # New Pester5 Configuration
        $configuration = [PesterConfiguration]@{
            Debug = @{
                ShowFullErrors = ($DebugPreference -eq 'Continue');
                WriteDebugMessages = ($DebugPreference -eq 'Continue');
            };
            Run = @{
                PassThru = $true;
                Container = New-PesterContainer -Path $Path -Data $TestData;
            };
            Filter = @{
                FullName = $TestName;
            };
            Should = @{
                ErrorAction = $ErrorActionPreference;
            };
            TestResult = @{
                Enabled = $true;
                OutputPath = $OutputPath;
                OutputFormat = $OutputFormat;
            };
        }
        
        # New Pester5 Invoke-Pester with Configuration
        Invoke-Pester -Configuration $configuration
    }
    
    if( $result -is [Management.Automation.Job] )
    {
        $result = $result | Receive-Job -Wait -AutoRemoveJob -InformationAction Ignore
    }

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