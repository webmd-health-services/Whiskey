
function Write-WhiskeyCommand
{
    [CmdletBinding()]
    param(
        [Whiskey.Context] $Context,

        [String] $Path,

        [Object[]] $ArgumentList
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $logArgumentList = & {
            if( $Path -match '\ ' )
            {
                '&'
            }
            $Path
            # Might have passed array of arrays.
            $ArgumentList | ForEach-Object { $_ | Write-Output }
        } |
        Where-Object { $null -ne $_ } |
        ForEach-Object {
            if ($_ -match '\ |;' -or $_ -eq '')
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
