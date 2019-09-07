function Install-WhiskeyNuGetPackage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Name,
        # The name of the NuGet package to download. 
        

        [Parameter()]
        [string] $Version,
        # The version of the package to download. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        

        [Parameter(Mandatory)]
        [string] $DownloadRoot
        # The root directory where the tools should be downloaded. The default is your build root.
        #
        # PowerShell modules are saved to `$DownloadRoot\Modules`.
        #
        # NuGet packages are saved to `$DownloadRoot\packages`.
    )
        if( -not $IsWindows )
        {
            Write-Error -Message ('Unable to install NuGet-based package {0} {1}: NuGet.exe is only supported on Windows.' -f $Name,$Version) -ErrorAction Stop
            return
        }
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
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
            & $nugetPath install $Name -version $Version -outputdirectory $packagesRoot | Write-CommandOutput -Description ('nuget.exe install')

            if ( $LASTEXITCODE )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NuGet.exe failed to install "{0}" with exit code "{1}"' -f $Name, $LASTEXITCODE)
                return
            }
            if( -not $nugetPath )
            {
                Write-Error -Message 
                return $null
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NuGet executed successfully when attempting to install "{0}" but the module was not found anywhere in the build root "{1}"' -f $nugetPath,$nuGetRoot)
                return
            }

        }
        return $nuGetRoot
}











