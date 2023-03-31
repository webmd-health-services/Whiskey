
function Invoke-WhiskeyNuGetPush
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Url,

        [Parameter(Mandatory)]
        [String]$ApiKey,

        [Parameter(Mandatory)]
        [String]$NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    Write-WhiskeyCommand -Path $NuGetPath -ArgumentList $Path, $Uri, $ApiKey
    & $NuGetPath push $Path -Source $Url -ApiKey $ApiKey
}
