
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

    $pathBefore = $env:PSModulePath -split [IO.Path]::PathSeparator
    try
    {
        $modulePaths = $pathBefore | Where-Object { $_ -ne $Path }
        $env:PSModulePath = $modulePaths -join [IO.Path]::PathSeparator
    }
    finally
    {
        Write-WhiskeyDebug "[Unregister-WhiskeyPSModulePath]  Changes to PSModulePath:"
        $pathNow = $env:PSModulePath -split [IO.Path]::PathSeparator
        $diff = Compare-Object -ReferenceObject $pathBefore -DifferenceObject $pathNow -IncludeEqual
        if( $diff )
        {
            $diff | Format-Table -AutoSize | Out-String | Write-WhiskeyDebug
        }
    }
}