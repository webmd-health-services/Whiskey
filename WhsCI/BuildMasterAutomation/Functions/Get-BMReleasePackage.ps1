
function Get-BMReleasePackage
{
    <#
    .SYNOPSIS
    Gets a release package from BuildMaster.

    .DESCRIPTION
    The `Get-BMReleasePackage` function gets a release package from BuildMaster.

    .EXAMPLE
    Get-BMReleasePackager -Session $session -Package $package

    Demonstrates how to get a package using a package object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # A object that represents what instance of BuildMaster to connect to. Use the `New-BMSession` function to create session objects.
        $Session,

        [Parameter(Mandatory=$true)]
        [object]
        # The package to get. Can be:
        #
        # * A package object with a `Package_Id`, `id`, `Package_Name`, or `name` parameter.
        # * A package ID (as an integer)
        # * A package name (as a string)
        $Package
    )

    Set-StrictMode -Version 'Latest'

    $parameter = @{ } | Add-BMObjectParameter -Name 'package' -Value $Package -PassThru
    Invoke-BMRestMethod -Session $Session -Name 'releases/packages' -Parameter $parameter
}
