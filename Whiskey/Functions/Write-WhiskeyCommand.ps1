
function Write-WhiskeyCommand
{
    [CmdletBinding()]
    param(
        [Whiskey.Context] $Context,

        [String] $Path,

        [Object[]] $ArgumentList,

        [switch] $NoIndent
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    # Might have passed array of arrays.
    $ArgumentList = & {
        $ArgumentList | ForEach-Object { $_ | Write-Output }
    }

    $logArgumentList = & {
            if( $Path -match '\ ' )
            {
                '&'
            }
            $Path
            $ArgumentList
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

    Write-WhiskeyInfo -Context $Context -Message ($logArgumentList -join ' ') -NoIndent:$NoIndent
    Write-WhiskeyVerbose -Context $Context -Message $Path
    $argumentPrefix = '  '
    foreach( $argument in $ArgumentList )
    {
        Write-WhiskeyVerbose -Context $Context -Message ('{0}{1}' -f $argumentPrefix,$argument)
    }
}
