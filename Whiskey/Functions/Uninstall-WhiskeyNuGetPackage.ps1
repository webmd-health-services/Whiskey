function Uninstall-WhiskeyNuGetPackage
{
    <#
    .SYNOPSIS
    Removes a NuGet package.

    .DESCRIPTION
    The `Uninstall-WhiskeyNuGetPackage` removes a NuGet package from the `packages` directory in your build root. Pass the name of the package to the `Name` parameter. By default, all versions of a package are removed. If you want to uninstall a specific version, pass that version to the `Version` parameter. Wildcards supported. Pass the path to your build root (the directory where your packages directory is located) to the `BuildRoot` parameter.

    .EXAMPLE
    Uninstall-WhiskeyNuGetPackage -Name 'NUnit.Runners -DownloadRoot 'C:\Rootdir\packages'

    Uninstall-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Rootdir\packages' -Version '2.6.4'

    Uninstall-WhiskeyNuGetPackage -Name 'NUnit.Runners -DownloadRoot 'C:\Rootdir\packages' -Version '2.*'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        # The name of the NuGet package to uninstall.
        [string]$Name,

        [Parameter(Mandatory)]
        # The build root where the build is currently running. Tools are installed here.
        [string]$BuildRoot,

        # The version of the package to uninstall. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        [String]$Version
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $Version )
    {
        $Version = '*'
    }

    $packagesRoot = Join-Path -Path $BuildRoot -ChildPath 'packages'
    $packageRoot = Join-Path -Path $packagesRoot -ChildPath ('{0}.{1}' -f $Name,$Version)
    if( (Test-Path -Path $packageRoot -PathType Container) )
    {
        Get-Item -Path $packageRoot | Remove-WhiskeyFileSystemItem
    }
}
