function New-WhiskeyFile
{
    [Whiskey.Task('File')]
    [CmdletBinding()]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowAbsolute)]
        [string[]]$Path,

        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [string]$Content,

        [switch]$Touch
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    foreach( $item in $Path )
    {
        if( Test-Path -Path (Split-Path -Path $item) -PathType Leaf )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                             -Message ('Parent directory of "{0}" is a file, not a directory.' -f $item)
            return
        }
        elseif( -not (Test-Path -Path $item) )
        {
            New-Item -Path $item -Value $Content -Force
        }
        elseif( Test-Path -Path $item -PathType Container )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                                -Message ('Unable to create file "{0}": a directory exists at that path.' -f $item)
            return
        }
        else
        {
            if( $Touch )
            {
                (Get-Item $Item).LastWriteTime = Get-Date
            }
            if( $Content ) 
            {
                Set-Content -Path $Path -Value $Content
            }
        }
    }
}