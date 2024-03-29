
function Invoke-WhiskeyNodeNspCheck
{
    [Whiskey.Task('NodeNspCheck', Obsolete,
        ObsoleteMessage='The "NodeNspCheck" task is obsolete and will be removed in a future version of Whiskey. Please use the "Npm" task instead. The NSP project shut down in September 2018 and was replaced with the `npm audit` command.')]
    [Whiskey.RequiresTool('Node', PathParameterName='NodePath', VersionParameterName='NodeVersion')]
    [Whiskey.RequiresNodeModule('nsp', PathParameterName='NspPath')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nspPath = Assert-WhiskeyNodeModulePath -Path $TaskParameter['NspPath'] -CommandPath 'bin\nsp' -ErrorAction Stop

    $nodePath = Assert-WhiskeyNodePath -Path $TaskParameter['NodePath'] -ErrorAction Stop

    $formattingArg = '--reporter'
    $isPreNsp3 = $TaskParameter.ContainsKey('Version') -and $TaskParameter['Version'] -match '^(0|1|2)\.'
    if( $isPreNsp3 )
    {
        $formattingArg = '--output'
    }

    Write-WhiskeyDebug -Context $TaskContext -Message 'Running NSP security check'
    $output = Invoke-Command -NoNewScope -ScriptBlock {
        param(
            $JsonOutputFormat
        )

        & $nodePath $nspPath 'check' $JsonOutputFormat 'json' 2>&1 |
            ForEach-Object { if( $_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
    } -ArgumentList $formattingArg

    Write-WhiskeyDebug -Context $TaskContext -Message 'COMPLETE'

    try
    {
        $results = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    }
    catch
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, did not run successfully as it did not return valid JSON (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$output)
        return
    }

    if ($Global:LASTEXITCODE -ne 0)
    {
        $summary = $results | Format-List | Out-String
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, found the following security vulnerabilities in your dependencies (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$summary)
        return
    }
}
