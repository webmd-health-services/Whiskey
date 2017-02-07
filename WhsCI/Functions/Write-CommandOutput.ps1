    Set-StrictMode -version 'latest'
    
    function Write-CommandOutput
    {
        param(
            [Parameter(ValueFromPipeline=$true)]
            [string]
            $InputObject
        )

        process
        {
            if( $InputObject -match '^WARNING\b' )
            {
                $InputObject | Write-Warning 
            }
            elseif( $InputObject -match '^ERROR\b' )
            {
                $InputObject | Write-Error
            }
            else
            {
                $InputObject | Write-Host
            }
        }
    }