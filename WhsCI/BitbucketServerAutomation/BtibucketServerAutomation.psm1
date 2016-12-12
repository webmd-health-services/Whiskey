
Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function '*'