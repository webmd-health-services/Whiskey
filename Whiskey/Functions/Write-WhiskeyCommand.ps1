
function Write-WhiskeyCommand
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$Context,

        [String]$Path,

        [String[]]$ArgumentList
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
    Write-WhiskeyVerbose -Context $TaskContext -Message $path -Verbose
    $argumentPrefix = '  '
    foreach( $argument in $ArgumentList )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('{0}{1}' -f $argumentPrefix,$argument) -Verbose
    }
}
