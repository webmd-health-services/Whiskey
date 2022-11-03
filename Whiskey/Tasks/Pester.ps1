
function Invoke-WhiskeyPesterTask
{
    [Whiskey.Task('Pester')]
    [Whiskey.RequiresPowerShellModule('Pester', ModuleInfoParameterName='PesterModuleInfo', Version='5.*', SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Management.Automation.PSModuleInfo] $PesterModuleInfo,

        [switch] $AsJob,

        [hashtable] $Configuration,

        [hashtable] $Container
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pesterManifestPath = $PesterModuleInfo.Path

    $exitCodePath = Join-Path -Path $TaskContext.Temp -ChildPath 'exitcode'

    $cmdArgList = @(
        (Get-Location).Path,
        $pesterManifestPath,
        $Configuration,
        $Container,
        $exitCodePath,
        @{
            'VerbosePreference' = $VerbosePreference;
            'DebugPreference' = $DebugPreference;
            'ProgressPreference' = $ProgressPreference;
            'WarningPreference' = $WarningPreference;
            'ErrorActionPreference' = $ErrorActionPreference;
        }
    )

    $scriptBlock = {
        param(
            [String] $WorkingDirectory,

            [String] $PesterManifestPath,

            [hashtable] $Configuration,

            [hashtable] $Container,

            [String] $ExitCodePath,

            [hashtable] $Preference
        )

        function Convert-ArrayList
        {
            param(
                [Parameter(Mandatory)]
                [Collections.ICollection] $InputObject
            )

            foreach( $entry in @($InputObject.GetEnumerator()) )
            {
                if( $entry.Value -is [Collections.ICollection] -and $entry.Value.PSobject.Properties.Name -contains 'Values' )
                {
                    Convert-ArrayList $entry.Value
                    continue
                }

                # PesterConfiguration only wants arrays for its lists. It doesn't handle any other list object.
                if( $entry.Value -is [Collections.IList] -and  $entry.Value -isnot [Array] )
                {
                    $InputObject[$entry.Key] = ($entry.Value.GetEnumerator() | ForEach-Object { $_ }) -as [Array]
                    continue
                }
            }
        }

        function Convert-Boolean
        {
            param(
                [Parameter(Mandatory)]
                [Collections.ICollection] $InputObject
            )

            foreach( $entry in @($InputObject.GetEnumerator()) )
            {
                if( $entry.Value -is [Collections.ICollection] -and $entry.Value.PSobject.Properties.Name -contains 'Values' )
                {
                    Convert-Boolean $entry.Value
                    continue
                }

                # PesterConfiguration does not accept strings for boolean values. True has to be $true
                if( $entry.Value -is [String] -and  $entry.Value -eq 'True' -or $entry.Value -eq 'False' )
                {
                    $InputObject[$entry.Key] = [System.Convert]::ToBoolean($entry.Value)
                    continue
                }
            }
        }

        function Get-PesterContainer
        {
            param(
                [Parameter(Mandatory)]
                [hashtable] $Container
            )

            if( $Container.ContainsKey('Path') )
            {
                return New-PesterContainer -Path $Container['Path'] -Data $Container['Data']
            }
            if( $Container.ContainsKey('ScriptBlock') )
            {
                if( $Container['ScriptBlock'] -isnot [scriptblock] )
                {
                    $Container['ScriptBlock'] = [scriptblock]::Create($Container['ScriptBlock'])
                }
                return New-PesterContainer -ScriptBlock $Container['ScriptBlock'] -Data $Container['Data']
            }
        }

        Set-Location -Path $WorkingDirectory

        $VerbosePreference = 'SilentlyContinue'
        Import-Module -Name $PesterManifestPath -Verbose:$false -WarningAction Ignore

        $VerbosePreference = $Preference['VerbosePreference']
        $DebugPreference = $Preference['DebugPreference']
        $ProgressPreference = $Preference['ProgressPreference']
        $WarningPreference = $Preference['WarningPreference']
        $ErrorActionPreference = $Preference['ErrorActionPreference']

        Convert-ArrayList -InputObject $Configuration
        Convert-Boolean -InputObject $Configuration

        # New Pester5 Invoke-Pester with Configuration
        $pesterConfiguration = New-PesterConfiguration -Hashtable $Configuration

        # If there is test data we have to set up a Pester Container
        if( $Container )
        {
            $pesterConfiguration.Run.Container = Get-PesterContainer -Container $Container
        }

        try
        {
            $LASTEXITCODE = 0
            Invoke-Pester -Configuration $pesterConfiguration
        }
        finally
        {
            Write-Debug "Pester  LASTEXITCODE  $($LASTEXITCODE)"
            $LASTEXITCODE | Set-Content -Path $ExitCodePath
        }
    }

    [int] $exitCode = 0
    if( $AsJob )
    {
        Start-Job -ArgumentList $cmdArgList -ScriptBlock $scriptBlock |
            Receive-Job -Wait -AutoRemoveJob -InformationAction Ignore
        $exitCode = Get-Content -Path $exitCodePath -ReadCount 1
    }
    else
    {
        Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $cmdArgList
        $exitCode = $LASTEXITCODE
    }

    if( $Configuration.ContainsKey('TestResult') -and `
        $Configuration['TestResult'] -is [Collections.ICollection] -and `
        $Configuration['TestResult'].ContainsKey('OutputPath') )
    {
        Publish-WhiskeyPesterTestResult -Path $Configuration['TestResult']['OutputPath']
    }

    if( $exitCode -ne 0 )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "Tests failed with exit code $($exitCode)."
    }
}