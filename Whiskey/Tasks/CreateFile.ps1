function New-WhiskeyFile
{
    [Whiskey.Task('CreateFile')]
    [CmdletBinding()]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowAbsolute)]
        [string[]]$Path,

        [Whiskey.Context]$TaskContext,

        [string]$Content,

        [bool]$Force,

        [bool]$Touch
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if (-not $TaskContext)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('No task context provided.')
        return
    }

    foreach($item in $Path)
    {
        if (Test-Path -Path $item)
        {
            if(Test-Path -Path $item -PathType Container)
            {
                Stop-WhiskeyTask -TaskContext $TaskContext `
                                 -Message ('Unable to create file ''{0}'': a directory exists at that path.' -f $item)
                return
            }

            if(-not $Force)
            {
                if($Touch)
                {
                    (Get-Item $Item).LastWriteTime = Get-Date
                    continue
                }

                Stop-WhiskeyTask -TaskContext $TaskContext `
                                 -Message ('''Path'' already exists. Please change ''Path'' to create new file.')
                return
            }
        }

        $parentPath = Split-Path -Path $item    
        if(-not (Test-Path -Path $parentPath) -and (-not $Force))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                             -Message ('Unable to create file ''{0}'': one or more of its parent directory, ''{1}'', does not exist. Either create this directory or use the ''Force'' property to create it.')
            return
        }

        if(Test-Path -Path $parentPath -PathType Leaf)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                             -Message ('Parent directory of ''{0}'' is a file, not a directory.' -f $item)
            return
        }

        New-Item -Path $item -Value $Content -Force
    }
}