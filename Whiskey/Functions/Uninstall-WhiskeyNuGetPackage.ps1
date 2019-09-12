function Uninstall-WhiskeyNuGetPackage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [string]$Name,
        # The name of the NuGet package to uninstall.

        [String]$Version,
        # The version of the package to uninstall. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [string]$BuildRoot
        # The build root where the build is currently running. Tools are installed here.
    )
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
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
            Remove-Item -Path $nuGetRoot -Recurse -Force
        }
}
