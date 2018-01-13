
function Remove-WhiskeyFileSystemItem
{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Path
    )

    Set-StrictMode -Version 'Latest'

    if( (Test-Path -Path $Path -PathType Leaf) )
    {
        Remove-Item -Path $Path -Force
    }
    elseif( (Test-Path -Path $Path -PathType Container) )
    {
        $emptyDir = Join-Path -Path $env:TEMP -ChildPath ([IO.Path]::GetRandomFileName())
        New-Item -Path $emptyDir -ItemType 'Directory' | Out-Null
        try
        {
            Invoke-WhiskeyRobocopy -Source $emptyDir -Destination $Path | Write-Verbose
            if( $LASTEXITCODE -ge 8 )
            {
                Write-Error -Message ('Failed to remove directory ''{0}''.' -f $Path)
                return
            }
            Remove-Item -Path $Path -Recurse -Force
        }
        finally
        {
            Remove-Item -Path $emptyDir -Recurse -Force
        }
    }
}