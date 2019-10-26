
function Write-WhiskeyLog
{
    [CmdletBinding()]
    [Whiskey.Task('Log')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$Context,

        [String]$Message,

        [String]$Level = 'Info'
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $levels = @('Error','Warning','Info','Verbose','Debug')
    if( $Level -notin $levels )
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('Property "Level" has an invalid value, "{0}". Valid values are {1}.' -f $Level,($levels -join ", "))
        return
    }

    Write-WhiskeyInfo -Context $Context -Message $Message -Level $Level
}
