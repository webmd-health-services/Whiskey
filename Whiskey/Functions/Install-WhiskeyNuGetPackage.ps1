function Install-WhiskeyNuGetPackage
{
    <#
    .SYNOPSIS
    Downloads and installs NuGet Packages.

    .DESCRIPTION
    The `Install-WhiskeyNuGetPackage` function uses NuGet.exe to download a NuGet package. Pass the name of the package to the `Name` parameter. By default, the latest non-prerelease version is downloaded. To download a specific version, pass that version to the `Version` parameter. Wildcards are supported. By default, packages are saved to a `packages` directory in the build root. If you want the packages directory to be in a different directory, pass the path to this different directory to the `DownloadRoot` parameter. The latest version of the NuGet command line is downloaded first. That version of NuGet.exe is then used to install the package.

    Please note that if you're using nuget.org as your package source, it has a bug preventing a list of all versions of a package. If you use nuget.org as your package source and your version contains a wildcard, you'll always get the latest version. We recommend you don't use wildcards if you use nuget.org.

    .EXAMPLE
    Install-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Buildroot\packages'

    Demonstrates how to call function with minimum parameters. `-Version` will default to latest available version.

    .EXAMPLE
    Install-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Buildroot\packages' -Version '2.6.4'

    Demonstrates how to call function with optional version parameter. 
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        # The name of the NuGet package to download. 
        [String]$Name,
        
        [Parameter(Mandatory)]
        # The root directory where the tools should be downloaded. The default is your build root.
        #
        # NuGet packages are saved to `$DownloadRoot\packages`.
        [String]$DownloadRoot,

        [String]$Version
        # The version of the package to download. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.

    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $IsWindows )
    {
        Write-WhiskeyError -Message ('Unable to install NuGet-based package {0} {1}: NuGet.exe is only supported on Windows.' -f $Name,$Version) -ErrorAction Stop
        return
    }
    $nugetPath = Join-Path -Path $whiskeyBinPath -ChildPath 'NuGet.exe' -Resolve
    $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'packages'
    $Version = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $Name -Version $Version -NugetPath $nugetPath
    if( -not $Version )
    {
        return
    }

    $nuGetRootName = '{0}.{1}' -f $Name,$Version
    $nuGetRoot = Join-Path -Path $packagesRoot -ChildPath $nuGetRootName
    Set-Item -Path 'env:EnableNuGetPackageRestore' -Value 'true'
    if( -not (Test-Path -Path $nuGetRoot -PathType Container) )
    {
        Invoke-Command -ScriptBlock {
            & $nugetPath install $Name -version $Version -outputdirectory $packagesRoot | Write-CommandOutput -Description ('nuget.exe install')
        }

        if ( $LASTEXITCODE )
        {
            Write-WhiskeyError ('NuGet.exe failed to install "{0}" with exit code "{1}"' -f $Name, $LASTEXITCODE) -ErrorAction Stop
            return
        }
        if( -not (Test-Path -Path $nugetRoot -PathType Container) )
        {
            Write-WhiskeyError ('NuGet executed successfully when attempting to install "{0}" but the module was not found anywhere in here "{1}"' -f $Name,$nuGetRoot) -ErrorAction Stop
            return
        }

    }
    return $nuGetRoot
}