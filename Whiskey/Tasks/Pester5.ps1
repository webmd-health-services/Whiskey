
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

        [hashtable] $TestData
    )

    function ConvertTo-Pester5Configuration
    {
        param(
            [hashtable] $config
        )

        foreach ($key in @($config.Keys)) {
            foreach ($subKey in @($config[$key].Keys)) {
                if($config[$key][$subkey].GetType().Name -eq 'ArrayList' ){
                    $config[$key][$subKey] = [String[]]$config[$key][$subKey]
                }
                if($config[$key][$subkey].GetType().Name -eq [String] -and $config[$key][$subkey] -eq 'True'){
                    $config[$key][$subkey] = $true
                }
                if($config[$key][$subkey].GetType().Name -eq [String] -and $config[$key][$subkey] -eq 'False'){
                    $config[$key][$subkey] = $false
                }
            }
        }
    }

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pesterManifestPath = $PesterModuleInfo.Path

    $cmdArgList = @(
        (Get-Location).Path,
        $pesterManifestPath,
        $Configuration,
        $TestData,
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

            [hashtable] $TestData,

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
        
        $DebugPreference = 'Continue'
        Write-Debug $Configuration.Run.Path.GetType()

        foreach ($key in @($Configuration.Keys)) {
            foreach ($subKey in @($Configuration[$key].Keys)) {
                if($Configuration[$key][$subkey].GetType().Name -eq 'ArrayList' ){
                    $Configuration[$key][$subKey] = [String[]]$Configuration[$key][$subKey]
                }
                if($Configuration[$key][$subkey].GetType().Name -eq [String] -and $Configuration[$key][$subkey] -eq 'True'){
                    $Configuration[$key][$subkey] = $true
                }
                if($Configuration[$key][$subkey].GetType().Name -eq [String] -and $Configuration[$key][$subkey] -eq 'False'){
                    $Configuration[$key][$subkey] = $false
                }
            }
        }

        # # Line below doesnt work for some reason when I try to pass $Configuration into function to handle array lists
        # ConvertTo-Pester5Configuration -config $Configuration

        Write-Debug $Configuration.Run.Path.GetType()

        # New Pester5 Invoke-Pester with Configuration
        $config = New-PesterConfiguration -Hashtable $Configuration

        # If there is test data we have to set up a Pester Container
        if($TestData -ne $null){
            $container = New-PesterContainer -Path $Configuration.Run.Path -Data $TestData
            $config.Run.Container = $container
        }

        Invoke-Pester -Configuration $config
    }
    
    if( $result -is [Management.Automation.Job] )
    {
        $result = $result | Receive-Job -Wait -AutoRemoveJob -InformationAction Ignore
    }

    Publish-WhiskeyPesterTestResult -Path $Configuration.TestResult.OutputPath
}