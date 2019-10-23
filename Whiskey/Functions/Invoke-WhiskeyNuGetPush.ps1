
function Invoke-WhiskeyNuGetPush
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    & $NuGetPath push $Path -Source $Uri -ApiKey $ApiKey

}