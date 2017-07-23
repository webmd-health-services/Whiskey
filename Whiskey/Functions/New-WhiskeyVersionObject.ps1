
function New-WhiskeyVersionObject
{
    [CmdletBinding()]
    param(
    )

    return [pscustomobject]@{
                                SemVer2 = $null;
                                SemVer2NoBuildMetadata = $null;
                                Version = $null;
                                SemVer1 = $null;
                            }
}
