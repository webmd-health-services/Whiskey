[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Path
)

Get-Item -Path $Path |
    Get-Content -Raw |
    ForEach-Object { ([xml]$_).SelectNodes('/test-results/test-suite/results/test-suite') } |
    ForEach-Object { [pscustomobject]@{ name = ($_.name | Split-Path -Leaf); duration = ([TimeSpan]::FromSeconds( $_.time )) } } |
    Sort-Object -Descending -Property 'duration'

