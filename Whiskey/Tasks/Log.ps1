
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

    $infoCmd = Get-Command -Name 'Write-WhiskeyInfo' -ModuleName 'Whiskey'
    if( -not $infoCmd )
    {
        Stop-WhiskeyTask -Context $Context -Message ('Umm, we can''t seem to find Whiskey''s Write-WhiskeyInfo function. Something pretty bad has gone wrong.')
        return
    }

    $levels = 
        $infoCmd.Parameters.GetEnumerator() | 
        Where-Object { $_.Key -eq 'Level' } |
        Select-Object -ExpandProperty 'Value' |
        Select-Object -ExpandProperty 'Attributes' |
        Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] } |
        Select-Object -ExpandProperty 'ValidValues'
    
    if( -not $levels )
    {
        Stop-WhiskeyTask -Context $Context -Message ('We can''t seem to find the ValidateSet attribute on the Write-WhiskeyInfo function''s Level parameter. Somethign pretty bad has gone wrong.')
        return
    }
        
    if( $Level -notin $levels )
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('Property "Level" has an invalid value, "{0}". Valid values are {1}.' -f $Level,($levels -join ", "))
        return
    }

    Write-WhiskeyInfo -Context $Context -Message $Message -Level $Level
}
