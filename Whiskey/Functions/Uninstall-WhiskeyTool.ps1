function Uninstall-WhiskeyTool
{
    <#
    .SYNOPSIS
    Removes a tool installed with `Install-WhiskeyTool`.

    .DESCRIPTION
    The `Uninstall-WhiskeyTool` function removes tools that were installed with `Install-WhiskeyTool`. It removes
    PowerShell modules, NuGet packages, Node, Node modules, and .NET Core SDKs that Whiskey installs into your build
    root. PowerShell modules are removed from the `Modules` direcory. NuGet packages are removed from the `packages`
    directory. Node and node modules are removed from the `.node` directory. The .NET Core SDK is removed from the
    `.dotnet` directory.

    When uninstalling a Node module, its name should be prefixed with `NodeModule::`, e.g. `NodeModule::rimraf`.

    Users of the `Whiskey` API typcially won't need to use this function. It is called by other `Whiskey` function so
    they have the tools they need.

    .EXAMPLE
    Uninstall-WhiskeyTool -ModuleName 'Pester'

    Demonstrates how to remove the `Pester` module from the default location.

    .EXAMPLE
    Uninstall-WhiskeyTool -NugetPackageName 'NUnit.Runners' -Version '2.6.4'

    Demonstrates how to uninstall a specific NuGet Package. In this case, NUnit Runners version 2.6.4 would be removed
    from the default location.

    .EXAMPLE
    Uninstall-WhiskeyTool -ModuleName 'Pester' -Path $forPath

    Demonstrates how to remove a Pester module from a specified path location other than the default location. In this
    case, Pester would be removed from the directory pointed to by the $forPath variable.

    .EXAMPLE
    Uninstall-WhiskeyTool -ModuleName 'Pester' -DownloadRoot $Root

    Demonstrates how to remove a Pester module from a DownloadRoot. In this case, Pester would be removed from
    `$Root\Modules`.

    .EXAMPLE
    Uninstall-WhiskeyTool -Name 'Node' -BuildRoot $TaskContext.BuildRoot

    Demonstrates how to uninstall Node from the `.node` directory in your build directory.

    .EXAMPLE
    Uninstall-WhiskeyTool -Name 'NodeModule::rimraf' -BuildRoot $TaskContext.BuildRoot

    Demonstrates how to uninstall the `rimraf` Node module from the `node_modules` directory in the Node directory in
    your build directory.

    .EXAMPLE
    Uninstall-WhiskeyTool -Name 'DotNet' -BuildRoot $TaskContext.BuildRoot

    Demonstrates how to uninstall the .NET Core SDK from the `.dotnet` directory in your build directory.
    #>
    [CmdletBinding()]
    param(
        # The tool attribute that defines what tool to uninstall.
        [Parameter(Mandatory, ParameterSetName='Tool')]
        [Whiskey.RequiresToolAttribute] $ToolInfo,

        # The name of the NuGet package to uninstall.
        [Parameter(Mandatory, ParameterSetName='NuGet')]
        [String] $NuGetPackageName,

        # The version of the package to uninstall. Must be a three part number, i.e. it must have a MAJOR, MINOR, and
        # BUILD number.
        [String] $Version,

        # The build directory where the build is currently running. Tools are installed here.
        [String] $BuildRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Remove-NuGetPackage
    {
        $packagesRoot = Join-Path -Path $BuildRoot -ChildPath 'packages'
        $nuGetRootName = '{0}.{1}' -f $NuGetPackageName,$Version
        $nuGetRoot = Join-Path -Path $packagesRoot -ChildPath $nuGetRootName

        if( (Test-Path -Path $nuGetRoot -PathType Container) )
        {
            Remove-Item -Path $nuGetRoot -Recurse -Force
        }
    }

    if( $PSCmdlet.ParameterSetName -eq 'NuGet' )
    {
        Remove-NuGetPackage
        return
    }

    $provider = $ToolInfo.ProviderName
    $name = $ToolInfo.Name

    if( $ToolInfo -is [Whiskey.RequiresPowerShellModuleAttribute] )
    {
        $provider = 'PowerShellModule'
    }

    switch( $provider )
    {
        'NodeModule'
        {
            # Don't do anything. All node modules require the Node tool to also be defined so they'll get deleted by
            # the Node deletion.
        }
        'NuGet'
        {
            Remove-NuGetPackage
        }
        'PowerShellModule'
        {
            Uninstall-WhiskeyPowerShellModule -Name $name -BuildRoot $BuildRoot
        }
        default
        {
            switch( $name )
            {
                'Node'
                {
                    Uninstall-WhiskeyNode -InstallRoot $BuildRoot
                }
                'DotNet'
                {
                    $dotnetToolRoot = Join-Path -Path $BuildRoot -ChildPath '.dotnet'
                    Remove-WhiskeyFileSystemItem -Path $dotnetToolRoot
                }
                default
                {
                    throw ('Unknown tool "{0}". The only supported tools are "Node" and "DotNet".' -f $name)
                }
            }
        }
    }
}
