
function Get-WhiskeyPSModulePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$PSModulesRoot,

        [switch]$Create
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $path = Join-Path -Path $PSModulesRoot -ChildPath 'PSModules' | Write-Output

    if( $Create -and -not (Test-Path -Path $path) )
    {
        New-Item -Path $path -ItemType 'Directory' | Out-Null
    }

    return $path
}