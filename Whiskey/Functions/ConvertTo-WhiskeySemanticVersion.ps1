
function ConvertTo-WhiskeySemanticVersion
{
    <#
    .SYNOPSIS
    Converts an object to a semantic version.

    .DESCRIPTION
    The `ConvertTo-WhiskeySemanticVersion` function converts strings, numbers, and date/time objects to semantic
    versions. If the conversion fails, it writes an error and you get nothing back. 

    .EXAMPLE
    '1.2.3' | ConvertTo-WhiskeySemanticVersion

    Demonstrates how to convert an object into a semantic version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        # The object to convert to a semantic version. Can be a version string, number, or date/time.
        [Object] $InputObject
    )

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( $InputObject -is [SemVersion.SemanticVersion] )
        {
            return $InputObject
        }
        elseif( $InputObject -is [DateTime] )
        {
            $InputObject = '{0}.{1}.{2}' -f $InputObject.Month,$InputObject.Day,$InputObject.Year
        }
        elseif( $InputObject -is [Double] )
        {
            $major,$minor = $InputObject.ToString('g') -split '\.'
            if( -not $minor )
            {
                $minor = '0'
            }
            $InputObject = '{0}.{1}.0' -f $major,$minor
        }
        elseif( $InputObject -is [int] )
        {
            $InputObject = '{0}.0.0' -f $InputObject
        }
        elseif( $InputObject -is [Version] )
        {
            if( $InputObject.Build -le -1 )
            {
                $InputObject = '{0}.0' -f $InputObject
            }
            else
            {
                $InputObject = $InputObject.ToString()
            }
        }

        [Version]$asVersion = $null
        [SemVersion.SemanticVersion]$semVersion = $null
        if( [SemVersion.SemanticVersion]::TryParse($InputObject, [ref]$semVersion) )
        {
            return $semVersion
        }

        if( [Version]::TryParse($InputObject, [ref]$asVersion) )
        {
            $major,$minor,$patch =
                @($asVersion.Major, $asVersion.Minor, $asVersion.Build) |
                ForEach-Object { if( $_ -eq -1 ) { return 0 } return $_ }
            return [SemVersion.SemanticVersion]::New($major, $minor, $patch)
        }

        [int] $asInt = 0
        if( [int]::TryParse($InputObject, [ref]$asInt) )
        {
            return [SemVersion.SemanticVersion]::New($asInt, 0, 0)
        }

        $original = $PSBoundParameters['InputObject']
        $msg = "Unable to convert ""[$($original.GetType().FullName)] $($original)"" to a semantic version."
        Write-WhiskeyError -Message $msg
    }
}

