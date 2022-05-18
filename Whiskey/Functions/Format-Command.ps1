
function Format-Command
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [String[]] $ArgumentList
    )

    begin
    {
        Set-StrictMode -version 'latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $cmdArgs = [Collections.Generic.List[String]]::New()
    }

    process
    {
        foreach( $cmdArg in $ArgumentList )
        {
            if( -not $cmdArg )
            {
                continue
            }

            if( $cmdArg.Contains(' ') -or $cmdArg.Contains(';') )
            {
                if( $cmdArg.Contains('"') )
                {
                    $cmdArg = $cmdArg.Replace('"', '""')
                }
    
                $cmdArg = """$($cmdArg)"""
            }

            $cmdArgs.Add($cmdArg)
        }
    }

    end
    {
        return $cmdArgs -join ' '
    }
}