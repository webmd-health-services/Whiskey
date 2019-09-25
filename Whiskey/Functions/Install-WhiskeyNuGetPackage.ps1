function Install-WhiskeyNuGetPackage
{
<#
    .SYNOPSIS
    Downloads and installs specified NuGet Packages.

    .DESCRIPTION
    The `Install-WhiskeyNuGetPackage` function downloads and installs the latest version of NuGet client if the client is not already installed, as well as the NuGet package specified. Both NuGet and the packages are downloaded into the `packages` directory in your buildroot. The path to the downloaded package is returned.

    .EXAMPLE
    Install-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Buildroot\packages'

    Install-WhiskeyNuGetPackage -Name 'NUnit.Runners' -DownloadRoot 'C:\Buildroot\packages' -Version '2.6.4'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        # The name of the NuGet package to download. 
        [string]$Name,
        
        [Parameter(Mandatory)]
        # The root directory where the tools should be downloaded. The default is your build root.
        #
        # PowerShell modules are saved to `$DownloadRoot\Modules`.
        #
        # NuGet packages are saved to `$DownloadRoot\packages`.
        [string]$DownloadRoot,

        [string]$Version
        # The version of the package to download. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.

    )
        if( -not $IsWindows )
        {
            Write-Error -Message ('Unable to install NuGet-based package {0} {1}: NuGet.exe is only supported on Windows.' -f $Name,$Version) -ErrorAction Stop
            return
        }
        $nugetPath = Join-Path -Path $whiskeyBinPath -ChildPath '\NuGet.exe' -Resolve
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
                Write-Error ('NuGet.exe failed to install "{0}" with exit code "{1}"' -f $Name, $LASTEXITCODE) -ErrorAction Stop
                return
            }
            if( -not (Test-Path -Path $nugetRoot -PathType Container) )
            {
                Write-Error ('NuGet executed successfully when attempting to install "{0}" but the module was not found anywhere in the build root "{1}"' -f $Name,$nuGetRoot) -ErrorAction Stop
                return
            }

        }
        return $nuGetRoot
}