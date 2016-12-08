
function New-WhsAppPackage
{
    <#
    .SYNOPSIS
    Creates an artifact.

    .DESCRIPTION
    The `New-WhsCIArtifact` function creates a new artifact.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the package file.
        $OutputFile,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The paths to include in the artifact.
        $Path,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The whitelist of files to include in the artifact.
        $Whitelist
    )

    Set-StrictMode -Version 'Latest'
}