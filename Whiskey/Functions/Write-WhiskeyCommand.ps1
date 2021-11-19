
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

    $Path = $Path | Resolve-WhiskeyRelativePath

    $logArgumentList = & {
            if( $Path -match '\ ' )
            {
                '&'
            }
            $Path
            $ArgumentList
        } |
        ForEach-Object { 
            if( $_ -match '\ ' )
            {
                '"{0}"' -f $_.Trim('"',"'")
            }
            else
            {
                $_
            }
        }

    Write-WhiskeyInfo -Context $TaskContext -Message ($logArgumentList -join ' ') -InformationAction Continue
    Write-WhiskeyDebug -Context $TaskContext -Message $Path -Verbose
    $argumentPrefix = '  '
    foreach( $argument in $ArgumentList )
    {
        Write-WhiskeyDebug -Context $TaskContext -Message ('{0}{1}' -f $argumentPrefix,$argument) -Verbose
    }
}
