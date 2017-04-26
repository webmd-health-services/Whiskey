function Uninstall-WhsCITool
{
    <#
    .SYNOPSIS
    Removes any specified artifacts of a tool previoulsy installed by the WhsCI module.

    .DESCRIPTION
    The `Uninstall-WhsCITool` function removes PowerShell modules or NuGet Packages previously installed in the WhsCI module. PowerShell modules and NuGet packages are removed from `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\Modules` and `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\Packages` respectively unless specified otherwise. 
    
    Users of the `WhsCI` API typcially won't need to use this function. It is called by other `WhsCI` function so they have the tools they need.

    .EXAMPLE
    Uninstall-WhsCITool -ModuleName 'Pester'

    Demonstrates how to remove the `Pester` module from the default location.
        
    .EXAMPLE
    Uninstall-WhsCITool -NugetPackageName 'NUnit.Runners' -Version '2.6.4'

    Demonstrates how to uninstall a specific NuGet Package. In this case, NUnit Runners version 2.6.4 would be removed from the default location. 

    .EXAMPLE
    Uninstall-WhsCITool -ModuleName 'Pester' -Path $forPath

    Demonstrates how to remove a Pester module from a specified path location other than the default location. In this case, Pester would be removed from the directory pointed to by the $forPath variable.
    
    .EXAMPLE
    Uninstall-WhsCITool -ModuleName 'Pester' -DownloadRoot $Root

    Demonstrates how to remove a Pester module from a DownloadRoot. In this case, Pester would be removed from `$Root\Modules`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='PowerShell')]
        [string]
        # The name of the PowerShell module to uninstall.
        $ModuleName,

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [string]
        # The name of the NuGet package to uninstall.
        $NuGetPackageName,

        [Parameter(Mandatory=$true)]
        [version]
        # The version of the package to uninstall. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        $Version,

        [string]
        # The root directory where the tools should be removed from. The default is `$env:LOCALAPPDATA\WebMD Health Services\WhsCI`.
        #
        # PowerShell modules will be uninstalled from to `$DownloadRoot\Modules`.
        #
        # NuGet packages are uninstalled from `$DownloadRoot\packages`.
        $DownloadRoot,

        [Parameter(ParameterSetName='PowerShell')]
        [String]
        # The Path parameter will take precedence over the DownloadRoot parameter and allows the user to specify the exact directory where they would like the PowerShell Module removed from.
        $Path
    )

    if( $DownloadRoot -and $Path )
    {
        Write-Error ('You have supplied a Path and DownloadRoot parameter to Uninstall-WhsCITool, where only one or the other is necessary, the Path parameter takes precedence and will be used. Please be sure this is the behavior you are expecting.')
    }

    if ( -not $DownloadRoot )
    {
        $DownloadRoot = Join-Path -path $env:LOCALAPPDATA -childPath '\WebMD Health Services\WhsCI'
    }

    if( $PSCmdlet.ParameterSetName -eq 'PowerShell' )
    {
        if ( $Path )
        {
            $modulesRoot = $Path
        }
        else
        {
            $modulesRoot = Join-Path -Path $DownloadRoot -ChildPath 'Modules'
        }
        #Remove modules saved by either PowerShell4 or PowerShell5
        $moduleRoots = @( ('{0}.{1}' -f $ModuleName, $Version), ('{0}\{1}' -f $ModuleName, $Version)  )
        forEach ($item in $moduleRoots)
        {
            $removeModule = (join-path -path $modulesRoot -ChildPath $item )
            if( Test-Path -Path $removeModule -PathType Container )
            {
                Remove-Item $removeModule -Recurse -Force
                return
            }
        }
    }
    elseif( $PSCmdlet.ParameterSetName -eq 'NuGet' )
    {
        $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'Packages'
        $nuGetRootName = '{0}.{1}' -f $NuGetPackageName,$Version
        $nuGetRoot = Join-Path -Path $packagesRoot -ChildPath $nuGetRootName
        
        if( (Test-Path -Path $nuGetRoot -PathType Container) )
        {
            Remove-Item -Path $nuGetRoot -Recurse -Force
        }
    }
}