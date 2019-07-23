function New-WhiskeyFile
{
    [Whiskey.Task("CreateFile")]
    [CmdletBinding()]
    param(
        [Parameter()]
        [Whiskey.Context]
        $TaskContext,

        [Parameter()]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Content,

        [Parameter()]
        [bool]
        $Force

    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ( -not $Path )
    {                                                         
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $pathErrorMessage
        return
    }

    if ( -not $TaskContext )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $pathExistsErrorMessage
        return
    }

    $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
    $Path = [System.IO.Path]::GetFullPath($Path)

    if ( -not ($Path.StartsWith($TaskContext.BuildRoot)) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $pathOutOfRoot
        return
    }

    if ( $Path | Test-Path )
    {
        if((Get-Item -Path $Path) -is [IO.DirectoryInfo])
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $pathExistsAsDirectoryMessage
            return
        }

        if ( $Force )
        {
            New-Item -Path $Path -Value $Content -Force
            return
        }

        Stop-WhiskeyTask -TaskContext $TaskContext -Message $pathExistsErrorMessage
        return
    }

    if( -not (Test-Path -Path ($Path | Split-Path)))
    {
        if ( $Force )
        {
            New-Item -Path $Path -Value $Content -Force
            return
        }

        Stop-WhiskeyTask -TaskContext $TaskContext -Message ($subdirectoryErrorMessage)
        return
    }

    New-Item -Path $Path -Value $Content
}

    #Error Messages
    $pathErrorMessage = @'
'Path' property is missing. Please set it to list of target locations to create new file.
'@
    $pathExistsErrorMessage = @'
'Path' already exists. Please change 'path' to create new file.
'@
    $pathExistsAsDirectoryMessage = @'
'Path' already points to a directory of the same name. Please change 'path' to create new file.
'@
    $subdirectoryErrorMessage = @'
'Path' contains subdirectories that do not exist. Use Force property to create entire path.
'@

    $pathOutOfRoot = @'
'Path' given is outside of root. Please change one or more elements of the 'path'.
'@