
function Invoke-WhiskeyNuGetPush
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Path,

        [Parameter(Mandatory)]
        [String] $Url,

        [String] $ApiKey,

        [Parameter(Mandatory)]
        [String] $NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $maskedApiKey = @()
    $apiKeyArgs = @()
    if ($ApiKey)
    {
        $maskedApiKey = @('-ApiKey', ('*' * $ApiKey.Length))
        $apiKeyArgs = @('-ApiKey', $ApiKey)
    }

    Write-WhiskeyCommand -Path $NuGetPath -ArgumentList (($Path, '-Source', $Url) + $maskedApiKey)
    & $NuGetPath push $Path -Source $Url $apiKeyArgs
}
