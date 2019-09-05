function New-WhiskeyFile
{
    [Whiskey.Task('File')]
    [CmdletBinding()]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false)]
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
        if( Test-Path -Path $item -PathType Container )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                             -Message ('Path "{0}" is a directory but must be a file.' -f $item)
            return
        }
        if( -not (Test-Path -Path $item) )
        {
            New-Item -Path $item -Value $Content -Force -ErrorAction Stop
        }
        if( $Touch )
        {
            (Get-Item $item).LastWriteTime = Get-Date
        }
        if( $Content ) 
        {
            Set-Content -Path $item -Value $Content
        }
    }
}