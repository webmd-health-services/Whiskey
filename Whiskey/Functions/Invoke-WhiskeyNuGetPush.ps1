
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
        $ApiKey
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve

    & $nugetPath push $Path -Source $Uri -ApiKey $ApiKey

}