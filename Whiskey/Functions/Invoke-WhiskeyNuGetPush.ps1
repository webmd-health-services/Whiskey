
function Invoke-WhiskeyNuGetPush
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Uri,

        [Parameter(Mandatory)]
        [String]$ApiKey,

        [Parameter(Mandatory)]
        [String]$NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    & $NuGetPath push $Path -Source $Uri -ApiKey $ApiKey

}
