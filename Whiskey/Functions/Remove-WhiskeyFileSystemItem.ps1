
function Remove-WhiskeyFileSystemItem
{
    <#
    .SYNOPSIS
    Deletes a file or directory.

    .DESCRIPTION
    The `Remove-WhiskeyFileSystemItem` deletes files and directories. Directories are deleted recursively. On Windows,
    this function tries to delete directories twice: once using PowerShell's Remove-Item cmdlet. If that fails, it
    assumes that there are paths too long and tries to use robocopy to delete the directory, since robocopy can handle
    files/directories whose paths are longer than the maximum 260 characters.

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
        [String] $Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyDebug -Message "Remove-WhiskeyFileSystemItem  BEGIN  ${Path}"

    if (-not (Test-Path -Path $Path))
    {
        Write-WhiskeyDebug -Message "  Path ""${Path}"" does not exist."
        return
    }

    if( (Test-Path -Path $Path -PathType Leaf))
    {
        Write-WhiskeyDebug "  Removing leaf ""${Path}""."
        Remove-Item -Path $Path -Force
        return
    }

    $eaArg = @{ }
    if ($IsWindows)
    {
        $eaArg['ErrorAction'] = 'Ignore'
    }

    Write-WhiskeyDebug "  Removing container ""${Path}""."
    Remove-Item -Path $Path -Recurse -Force @eaArg

    # It was deleted. We can go now.
    if (-not (Test-Path -Path $Path))
    {
        return
    }

    # It still exists. If we're on Windows it could be because paths are too long so on other platforms do nothing
    # (return the original error) but on Windows try deleting with Robocopy.
    if (-not $IsWindows)
    {
        return
    }

    $emptyDir = Get-WhiskeyTempPath -Name 'Empty'
    try
    {
        Write-WhiskeyDebug "  Removing container ""${Path}"" with Robocopy."
        Invoke-WhiskeyRobocopy -Source $emptyDir -Destination $Path
        Remove-Item -Path $Path -Recurse -Force
    }
    finally
    {
        if (Test-Path -Path $emptyDir)
        {
            Remove-Item -Path $emptyDir -Recurse -Force
        }
    }
    
    Write-WhiskeyDebug -Message ('Remove-WhiskeyFileSystemItem  END')
}
