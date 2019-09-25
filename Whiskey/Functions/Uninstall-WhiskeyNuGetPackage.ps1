function Uninstall-WhiskeyNuGetPackage
{
<#
    .SYNOPSIS
    Removes a package installed with `Install-WhiskeyNuGetPackage`.

    .DESCRIPTION
    The `Install-WhiskeyNuGetPackage` removes the NuGet package specified if it exists. NuGetPackages are removed from the `packages` directory in your buildroot. `Uninstall-WhiskeyNuGetPackage` returns void.

    .EXAMPLE
    Uninstall-WhiskeyNuGetPackage -Name 'NUnit.Runners.2.6.4' -DownloadRoot 'C:\Rootdir\...\packages'

    Uninstall-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Rootdir\...\packages' -Version '2.6.4'
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
        $nugetPath = Join-Path -Path $whiskeyBinPath -ChildPath '\NuGet.exe' -Resolve
        $Version = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $Name -Version $Version -NugetPath $nugetPath
        if( -not $Version )
        {
            return
        }
        $packagesRoot = Join-Path -Path $BuildRoot -ChildPath 'packages'
        $nuGetRootName = '{0}.{1}' -f $Name,$Version
        $nuGetRoot = Join-Path -Path $packagesRoot -ChildPath $nuGetRootName
        
        if( (Test-Path -Path $nuGetRoot -PathType Container) )
        {
            Remove-WhiskeyFileSystemItem -Path $nuGetRoot
        }
}
