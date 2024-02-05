
function Get-WhiskeyTempPath
{
    [CmdletBinding()]
    param(
        [Object] $Context,

        [String] $Name
    )

    $tempPath = [IO.Path]::GetTempPath()
    if (-not $Context)
    {
        $Context = Get-WhiskeyContext
    }

    if ($Context)
    {
        $tempPath = $Context.Temp.FullName
    }

    if ($Name)
    {
        $tempPath = Join-Path -Path $tempPath -ChildPath $Name
    }

    if (-not (Test-Path -Path $tempPath))
    {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }

    return $tempPath
}
