function Write-CommandOutput
{
    param(
        [Parameter(ValueFromPipeline)]
        [String]$InputObject,

        [Parameter(Mandatory)]
        [String]$Description
    )

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( $InputObject -match '^WARNING\b' )
        {
            $InputObject | Write-WhiskeyWarning 
        }
        elseif( $InputObject -match '^ERROR\b' )
        {
            $InputObject | Write-WhiskeyError 
        }
        else
        {
            $InputObject | 
                ForEach-Object { '[{0}] {1}' -f $Description,$_ } | 
                Write-WhiskeyVerbose 
        }
    }
}
