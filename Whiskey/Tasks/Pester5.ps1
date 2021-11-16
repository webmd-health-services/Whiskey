
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
        
        [Management.Automation.PSModuleInfo] $PesterModuleInfo,

        [switch] $AsJob,

        [hashtable] $Configuration,

        [hashtable] $Container
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pesterManifestPath = $PesterModuleInfo.Path

    $cmdArgList = @(
        (Get-Location).Path,
        $pesterManifestPath,
        $Configuration,
        $Container,
        @{
            'VerbosePreference' = $VerbosePreference;
            'DebugPreference' = $DebugPreference;
            'ProgressPreference' = $ProgressPreference;
            'WarningPreference' = $WarningPreference;
            'ErrorActionPreference' = $ErrorActionPreference;
        }
    )

    $cmdName = 'Invoke-Command'
    if( $AsJob )
    {
        $cmdName = 'Start-Job'
    }

    $result = & $cmdName -ArgumentList $cmdArgList -ScriptBlock {
        param(
            [String] $WorkingDirectory,

            [String] $PesterManifestPath,

            [hashtable] $Configuration,

            [hashtable] $Container,

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
                return New-PesterContainer -Path $Container.Path -Data $Container.Data
            }
            if( $Container.ContainsKey('ScriptBlock') )
            {
                return New-PesterContainer -ScriptBlock $Container.ScriptBlock
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
        
        $DebugPreference = 'Continue'
        Write-Debug $Configuration.Run.Path.GetType()

        Convert-ArrayList -InputObject $Configuration
        Convert-Boolean -InputObject $Configuration

        Write-Debug $Configuration.Run.Path.GetType()

        # New Pester5 Invoke-Pester with Configuration
        $pesterConfiguration = New-PesterConfiguration -Hashtable $Configuration

        # If there is test data we have to set up a Pester Container
        if($Container -ne $null){
            $pesterConfiguration.Run.Container = Get-PesterContainer -Container $Container
        }

        Invoke-Pester -Configuration $pesterConfiguration
    }
    
    if( $result -is [Management.Automation.Job] )
    {
        $result = $result | Receive-Job -Wait -AutoRemoveJob -InformationAction Ignore
    }

    if( $Configuration.ContainsKey('TestResult') -and `
    $Configuration['TestResult'] -is [Collections.ICollection] `
    -and $Configuration['TestResult'].Contains('OutputPath') )
    {
        Publish-WhiskeyPesterTestResult -Path $Configuration['TestResult']['OutputPath']
    }
}