
function Invoke-WhiskeyPester3Task
{
    [Whiskey.Task('Pester3',Platform='Windows', Obsolete,
                  ObsoleteMessage='The "Pester3" task is obsolete and is no longer supported.')]
    [Whiskey.RequiresPowerShellModule('Pester', ModuleInfoParameterName='PesterModuleInfo', Version='3.*', SkipImport)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory)]
        [String[]]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $outputFile = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('pester+{0}.xml' -f [IO.Path]::GetRandomFileName())
    $outputFile = [IO.Path]::GetFullPath($outputFile)

    $moduleInfo = $TaskParameter['PesterModuleInfo']
    $pesterManifestPath = $moduleInfo.Path

    $workingDirectory = (Get-Location).Path

    # We do this in the background so we can test this with Pester.
    $job = Start-Job -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference
        $DebugPreference = $using:DebugPreference
        $ProgressPreference = $using:ProgressPreference
        $WarningPreference = $using:WarningPreference
        $ErrorActionPreference = $using:ErrorActionPreference

        Set-Location -Path $using:workingDirectory

        $script = $using:Path
        $pesterManifestPath = $using:pesterManifestPath
        $outputFile = $using:outputFile

        Invoke-Command -ScriptBlock {
                                        $VerbosePreference = 'SilentlyContinue'
                                        Import-Module -Name $pesterManifestPath -WarningAction Ignore
                                    }

        Invoke-Pester -Script $script -OutputFile $outputFile -OutputFormat NUnitXml -PassThru
    }


    # There's a bug where Write-Host output gets duplicated by Receive-Job if $InformationPreference is set to "Continue".
    # Since Pester uses Write-Host, this is a workaround to avoid seeing duplicate Pester output.
    do
    {
        $job | Receive-Job -InformationAction SilentlyContinue
    }
    while( -not ($job | Wait-Job -Timeout 1) )

    $job | Receive-Job -InformationAction SilentlyContinue

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

