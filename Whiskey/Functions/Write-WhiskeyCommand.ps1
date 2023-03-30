
function Write-WhiskeyCommand
{
    [CmdletBinding()]
    param(
        [Whiskey.Context] $Context,

        [String] $Path,

        [String[]] $ArgumentList
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $logArgumentList = & {
            if( $Path -match '\ ' )
            {
                '&'
            }
            $Path
            $ArgumentList
        } |
        ForEach-Object {
            if( $_ -match '\ |;' )
            {
                '"{0}"' -f $_.Trim('"',"'")
            }
            else
            {
                $_
            }
        }

    Write-WhiskeyInfo -Context $Context -Message ($logArgumentList -join ' ')
    Write-WhiskeyVerbose -Context $Context -Message $Path
    $argumentPrefix = '  '
    foreach( $argument in $ArgumentList )
    {
        Write-WhiskeyVerbose -Context $Context -Message ('{0}{1}' -f $argumentPrefix,$argument)
    }
}
