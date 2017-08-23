
function Invoke-WhiskeyNuGetPush
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        $Uri,

        [Parameter(Mandatory=$true)]
        [string]
        $ApiKey,

        [string]
        $NuGetPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve)
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    & $NuGetPath push $Path -Source $Uri -ApiKey $ApiKey

}