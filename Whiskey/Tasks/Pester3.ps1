
function Invoke-WhiskeyPester3Task
{
    [Whiskey.Task('Pester3',Platform='Windows')]
    [Whiskey.RequiresPowerShellModule('Pester',ModuleInfoParameterName='PesterModuleInfo',Version='3.*',VersionParameterName='Version',SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of Pester Tests to run with Pester3, e.g.

        Build:
        - Pester3:
            Path:
            - My.Tests.ps1
            - Tests')
        return
    }

    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'

    $outputFile = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
    $outputFile = [IO.Path]::GetFullPath($outputFile)

    $moduleInfo = $TaskParameter['PesterModuleInfo']
    $pesterManifestPath = $moduleInfo.Path

    # We do this in the background so we can test this with Pester.
    $job = Start-Job -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference
        $DebugPreference = $using:DebugPreference
        $ProgressPreference = $using:ProgressPreference
        $WarningPreference = $using:WarningPreference
        $ErrorActionPreference = $using:ErrorActionPreference

        $script = $using:Path
        $pesterManifestPath = $using:pesterManifestPath
        $outputFile = $using:outputFile

        Invoke-Command -ScriptBlock {
                                        $VerbosePreference = 'SilentlyContinue'
                                        Import-Module -Name $pesterManifestPath
                                    }

        Invoke-Pester -Script $script -OutputFile $outputFile -OutputFormat NUnitXml -PassThru
    }

    # There's a bug where Write-Host output gets duplicated by Receive-Job if $InformationPreference is set to "Continue".
    # Since Pester uses Write-Host, this is a workaround to avoid seeing duplicate Pester output.
    $informationActionParameter = @{ }
    if( (Get-Command -Name 'Receive-Job' -ParameterName 'InformationAction') )
    {
        $informationActionParameter['InformationAction'] = 'SilentlyContinue'
    }

    do
    {
        $job | Receive-Job @informationActionParameter
    }
    while( -not ($job | Wait-Job -Timeout 1) )

    $job | Receive-Job @informationActionParameter

    Publish-WhiskeyPesterTestResult -Path $outputFile

    $result = [xml](Get-Content -Path $outputFile -Raw)

    if( -not $result )
    {
        throw ('Unable to parse Pester output XML report ''{0}''.' -f $outputFile)
    }

    if( $result.'test-results'.errors -ne '0' -or $result.'test-results'.failures -ne '0' )
    {
        throw ('Pester tests failed.')
    }
}

