
function Remove-WhiskeyFileSystemItem
{
    <#
    .SYNOPSIS
    Deletes a file or directory.

    .DESCRIPTION
    The `Remove-WhiskeyFileSystemItem` deletes files and directories. Directories are deleted recursively. On Windows, this function uses robocopy to delete directories, since it can handle files/directories whose paths are longer than the maximum 260 characters.

    If the file or directory doesn't exist, nothing happens.

    The path to delete should be absolute or relative to the current working directory.

    This function won't fail a build. If you want it to fail a build, pass the `-ErrorAction Stop` parameter.

    .EXAMPLE
    Remove-WhiskeyFileSystemItem -Path 'C:\some\file'

    Demonstrates how to delete a file.

    .EXAMPLE
    Remove-WhiskeyFilesystemItem -Path 'C:\project\node_modules'

    Demonstrates how to delete a directory.

    .EXAMPLE
    Remove-WhiskeyFileSystemItem -Path 'C:\project\node_modules' -ErrorAction Stop

    Demonstrates how to fail a build if the delete fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyDebug -Message ('Remove-WhiskeyFileSystemItem  BEGIN  {0}' -f $Path)
    if( (Test-Path -Path $Path -PathType Leaf) )
    {
        Remove-Item -Path $Path -Force
    }
    elseif( (Test-Path -Path $Path -PathType Container) )
    {
        if( $IsWindows )
        {
            $logPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('whiskey.robocopy.{0}.log' -f ([IO.Path]::GetRandomFileName()))
            $emptyDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
            $deleteLog = $true
            New-Item -Path $emptyDir -ItemType 'Directory' | Out-Null
            try
            {
                Invoke-WhiskeyRobocopy -Source $emptyDir -Destination $Path -LogPath $logPath | Out-Null
                if( $LASTEXITCODE -ge 8 )
                {
                    $deleteLog = $false
                    Write-WhiskeyError -Message ('Failed to remove directory "{0}". See "{1}" for more information.' -f $Path,$logPath)
                    return
                }
                Remove-Item -Path $Path -Recurse -Force
            }
            finally
            {
                if( $deleteLog )
                {
                    Remove-Item -Path $logPath -ErrorAction Ignore -Force
                }
                Remove-Item -Path $emptyDir -Recurse -Force
            }
        }
        else
        {
            Remove-Item -Path $Path -Recurse -Force
        }
    }
    Write-WhiskeyDebug -Message ('Remove-WhiskeyFileSystemItem  END')
}
