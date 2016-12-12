
function ConvertTo-SemanticVersion
{
    <#
    .SYNOPSIS
    Converts an object to a semantic version.

    .DESCRIPTION
    The `ConvertTo-SemanticVersion` function converts strings and date/time objects to semantic versions. If the conversion fails, it writes an error and you get nothing back.

    Whey date/time objects, do you say? Because when our YAML parser encounters some version numbers, it sees them as date/times, instead. For example, our YAML parsers sees

        Version: 1.2.3

    as January 2nd, 2003. In almost all situations, the above YAML is because someone forgot to put strings around it, or didn't know they needed to.

    .EXAMPLE
    '1.2.3' | ConvertTo-SemanticVersion

    Demonstrates how to convert a string to a semantic version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]
        $InputObject
    )

    process
    {
        if( $InputObject -is [datetime] )
        {
            $patch = $InputObject.Year
            if( $patch -ge 2000 )
            {
                $patch -= 2000
            }
            elseif( $patch -ge 1900 )
            {
                $patch -= 1900
            }
            $InputObject = '{0}.{1}.{2}' -f $InputObject.Month,$InputObject.Day,$patch
        }

        $semVersion = $null
        if( ([SemVersion.SemanticVersion]::TryParse($InputObject,[ref]$semVersion)) )
        {
            return $semVersion
        }

        Write-Error -Message ('Unable to convert ''{0}'' of type ''{1}'' to a semantic version.' -f $PSBoundParameters['InputObject'],$PSBoundParameters['InputObject'].GetType().FullName)
    }
}
    
