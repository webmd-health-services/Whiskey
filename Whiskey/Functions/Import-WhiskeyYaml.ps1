
function Import-WhiskeyYaml
{
    param(
        $Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $config = Get-Content -Path $Path -Raw | ConvertFrom-Yaml
    if( -not $config )
    {
        $config = @{} 
    }

    if( $config -is [string] )
    {
        $config = @{ $config = '' }
    }

    return $config
}