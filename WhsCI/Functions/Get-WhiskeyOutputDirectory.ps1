
function Get-WhsCIOutputDirectory
{
    <#
    .SYNOPSIS
    Gets the path to the directory where build output should go.

    .DESCRIPTION
    The `Get-WhsCIOutputDirectory` gets the path to the directory where build output should go. Test results, binaries, packages, reports, etc. should all be put into this directory. You pass it a working directory, which is usually the path to the root of the repository of the curent build.

    If the directory doesn't exist, it is created.

    To remove anything from an existing output directory, use the `Clear` switch.

    .EXAMPLE
    Get-WhsCIOutputDirectory -WorkingDirectory $env:WORKSPACE

    Demonstrates how to call this function. You pass it the path to the working directory and it returns the path to a directory where you can put build output.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the working directory, i.e. the root of the repository being built.
        $WorkingDirectory,

        [Switch]
        # Removes anything in the output directory, if it exists.
        $Clear
    )

    Set-StrictMode -Version 'Latest'

    $outputDirectory = Join-Path -Path $WorkingDirectory -ChildPath '.output'
    if( -not (Test-Path -Path $outputDirectory -PathType Container) )
    {
        New-Item -Path $outputDirectory -ItemType 'Directory' -Force | Out-Null
    }

    if( $Clear )
    {
        Get-ChildItem -Path $outputDirectory | Remove-Item -Recurse -Force
    }

    return $outputDirectory
}