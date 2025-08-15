
function Invoke-WhiskeyPesterTask
{
    [Whiskey.Task('Pester')]
    [Whiskey.RequiresPowerShellModule('Pester', Version='5.*', ModuleInfoParameterName='PesterModuleInfo', SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Management.Automation.PSModuleInfo] $PesterModuleInfo,

        [hashtable] $Configuration,

        [hashtable] $Container
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pesterManifestPath = $PesterModuleInfo.Path

    $exitCodePath = Join-Path -Path $TaskContext.Temp -ChildPath 'exitcode'

    $cmdArgList = @{
        WorkingDirectory = (Get-Location).Path;
        PesterManifestPath = $pesterManifestPath;
        Configuration = $Configuration;
        Container = $Container;
        ExitCodePath = $exitCodePath;
        Preference = @{
            'VerbosePreference' = [String]$VerbosePreference;
            'DebugPreference' = [String]$DebugPreference;
            'ProgressPreference' = [String]$ProgressPreference;
            'WarningPreference' = [String]$WarningPreference;
            'ErrorActionPreference' = [String]$ErrorActionPreference;
            'InformationPreference' = [String]$InformationPreference;
        }
    }

    $cmdName = 'powershell'
    if ($PSVersionTable['PSEdition'] -eq 'Core')
    {
        $cmdName = 'pwsh'
    }
    $invokePesterPath = Join-Path -Path $script:whiskeyBinPath -ChildPath 'Invoke-Pester.ps1' -Resolve
    Write-WhiskeyDebug "Starting ${cmdName}"
    $parameterJson = $cmdArgList | ConvertTo-Json -Depth 100
    $parameterBytes = [Text.Encoding]::Unicode.GetBytes($parameterJson)
    $parameterBase64 = [Convert]::ToBase64String($parameterBytes)
    & $cmdName -NoProfile -NonInteractive -File $invokePesterPath -ParameterBase64 $parameterBase64
    Write-WhiskeyDebug "Done     ${cmdName}"

    if (-not (Test-Path -Path $exitCodePath -PathType Leaf))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "Pester task failed to run tests."
        return
    }

    [int] $exitCode = Get-Content -Path $exitCodePath -ReadCount 1
    if( $exitCode -ne 0 )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "Tests failed with exit code $($exitCode)."
    }
}