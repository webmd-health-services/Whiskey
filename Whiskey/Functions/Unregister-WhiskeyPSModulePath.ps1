
function Unregister-WhiskeyPSModulePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='FromUser')]
        [String]$Path,

        [Parameter(Mandatory,ParameterSetName='FromWhiskey')]
        [String]$PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( $PSCmdlet.ParameterSetName -eq 'FromWhiskey' )
    {
        $Path = Get-WhiskeyPSModulePath -PSModulesRoot $PSModulesRoot
    }

    $modulePaths = $env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { $_ -ne $Path }
    $env:PSModulePath = $modulePaths -join [IO.Path]::PathSeparator
}