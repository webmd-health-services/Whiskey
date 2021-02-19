
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
        [hashtable]$TaskParameter,

        [String[]]$Arguments
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $licenseCheckerPath = Assert-WhiskeyNodeModulePath -Path $TaskParameter['LicenseCheckerPath'] -CommandPath 'bin\license-checker' -ErrorAction Stop

    $nodePath = Assert-WhiskeyNodePath -Path $TaskParameter['NodePath'] -ErrorAction Stop

    Write-WhiskeyDebug -Context $TaskContext -Message ('Generating license report')
    Invoke-Command -NoNewScope -ScriptBlock {
        & $nodePath $licenseCheckerPath $Arguments 
    }
    if( $LASTEXITCODE -eq 1 )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "license-checker returned a non-zero exit code. See above output for more details."
        return
    }
    
    Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
}
