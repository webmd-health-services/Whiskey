
function Convert-WhiskeyPathDirectorySeparator
{
    <#
    .SYNOPSIS
    Converts the directory separators in a path to the preferred separator for the current platform.

    .DESCRIPTION
    The `Convert-WhiskeyPathDirectorySeparator` function uses PowerShell's `Join-Path` cmdlet to convert the directory separator characters in a path to the ones for the current platform. The path does not have to exist. It joins the path with the `.` character, then trims all periods and 

    .EXAMPLE
    $Path | Convert-WhiskeyPathDirectorySeparator

    Demonstrates how to use this function by piping paths to it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [String]$Path
    )

    process
    {
        $Path = Join-Path -Path $Path -ChildPath '.'
        # Take off the '.' period we added.
        $Path = $Path.TrimEnd('.')
        # Now remove the extra separator we added.
        return $Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar);
    }
}