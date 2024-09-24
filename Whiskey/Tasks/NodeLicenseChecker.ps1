
function Invoke-WhiskeyNodeLicenseChecker
{
    [CmdletBinding()]
    [Whiskey.Task('NodeLicenseChecker',
        Obsolete,
        ObsoleteMessage='The "NodeLicenseChecker" task is obsolete and will be removed in a future version of ' +
                        'Whiskey. Instead, install a global version of Node.js and add commands to your whiskey.yml ' +
                        'script to install and run the license checker. If you want to install a local copy of ' +
                        'Node.js, use the "InstallNodeJs" task, which will add Node.js commands to your build''s ' +
                        'PATH environment variable.')]
    [Whiskey.RequiresTool('Node', PathParameterName='NodePath', VersionParameterName='NodeVersion')]
    [Whiskey.RequiresNodeModule('license-checker', PathParameterName='LicenseCheckerPath')]
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
