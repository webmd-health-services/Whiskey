
function Invoke-WhiskeyNodeLicenseChecker
{
    [CmdletBinding()]
    [Whiskey.Task('NodeLicenseChecker')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [Whiskey.RequiresTool('NodeModule::license-checker',PathParameterName='LicenseCheckerPath',VersionParameterName='Version')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $licenseCheckerPath = Assert-WhiskeyNodeModulePath -Path $TaskParameter['LicenseCheckerPath'] -CommandPath 'bin\license-checker' -ErrorAction Stop

    $nodePath = Assert-WhiskeyNodePath -Path $TaskParameter['NodePath'] -ErrorAction Stop

    Write-WhiskeyDebug -Context $TaskContext -Message ('Generating license report')
    $reportJson = Invoke-Command -NoNewScope -ScriptBlock {
        & $nodePath $licenseCheckerPath '--json' '--failOn' 'AGPL-1.0-or-later;GPL-1.0-or-later;LGPL-2.0-or-later'
    }
    if( $LASTEXITCODE -eq 1 )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "license-checker reported a prohibited GPL license. See above for more details."
        return
    }
    
    Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')

    $report = Invoke-Command -NoNewScope -ScriptBlock {
        ($reportJson -join [Environment]::NewLine) | ConvertFrom-Json
    }
    if (-not $report)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'License Checker failed to output a valid JSON report.'
        return
    }

    Write-WhiskeyDebug -Context $TaskContext -Message 'Converting license report.'
    # The default license checker report has a crazy format. It is an object with properties for each module.
    # Let's transform it to a more sane format: an array of objects.
    [Object[]]$newReport = 
        $report |
        Get-Member -MemberType NoteProperty |
        Select-Object -ExpandProperty 'Name' |
        ForEach-Object { $report.$_ | Add-Member -MemberType NoteProperty -Name 'name' -Value $_ -PassThru }

    # show the report
    $newReport | Sort-Object -Property 'licenses','name' | Format-Table -Property 'licenses','name' -AutoSize | Out-String | Write-WhiskeyVerbose -Context $TaskContext

    $licensePath = 'node-license-checker-report.json'
    $licensePath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath $licensePath
    ConvertTo-Json -InputObject $newReport -Depth 100 | Set-Content -Path $licensePath
    Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
}
