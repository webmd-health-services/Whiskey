
function Format-Path
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $InputObject
    )

    process
    {
        if ($InputObject.Contains(' '))
        {
            return """${InputObject}"""
        }

        return $InputObject
    }
}
