
function Invoke-WhiskeyDotNetPack
{
    <#
    .SYNOPSIS
    Creates a NuGet package from a .NET Core project.

    .DESCRIPTION
    The `DotNetPack` tasks runs the `dotnet.exe pack` command to create a NuGet package from .NET projects targeting .NET Core and .NET Standard. Pass a list of solution files or .NET Core project files to the `Path` property. If no files are provided to `Path`, then the .NET Core SDK will search for any solution or project files in the working directory and create packages for those. If the `dotnet.exe pack` command returns a non-zero exit code the build will fail.

    # Properties

    * `Argument`: a list of additional arguments to pass to the `dotnet.exe pack` command.
    * `Path`: a list of paths to .NET Core solution or project files to create NuGet packages from. If not specified, any solution or project files in the task working directory will be packaged.
    * `SdkVersion`: the version of the .NET Core SDK to use to package the project. Supports wildcard values. If not specified, the task will look for the SDK version from the `global.json` file if it is found in the task working directory or the Whiskey build root. If no SDK version can be located, the task will default to using the SDK version that comes with the latest LTS release of the .NET Core runtime. Whiskey will *always* update the SDK version property in the `global.json` file with the SDK version that task is running with. If no `global.json` file exists, one will be created in the Whiskey build root.
    * `Symbols`: a boolean value indicating whether or not to also create a package with symbols. The symbols package will be created next to the regular package in the build output directory. Defaults to `false`.
    * `Verbosity`: sets the verbosity level of dotnet.exe's output. For developers, the default is dotnet.exe's default verbosity. On build servers, the default is `detailed`. Allowed values are `q[uiet]`, `m[inimal]`, `n[ormal]`, `d[etailed]`, and `diag[nostic]`.

    # Examples

    ## Example 1

        BuildTasks:
        - DotNetPack:
            Path:
            - DotNetCoreSolution.sln

    Demonstrates creating a NuGet package for all projects in the DotNetCoreSolution.sln solution file with the `dotnet pack` command.

    ## Example 2

        BuildTasks:
        - DotNetPack:
            Path:
            - DotNetCoreSolution.sln
            Symbols: true
            Verbosity: normal

    Demonstrates creating a NuGet regular package and symbols package for all projects within a solution file and running `dotnet pack` with normal verbosity.

    ## Example 3

        BuildTasks:
        - DotNetPack:
            Path:
            - src\DotNetStandardLibrary.csproj
            - src\DotNetCoreApp.csproj
            Argument:
            - --include-source

    Demonstrates creating a NuGet package for multiple projects found in the `$(WHISKEY_BUILD_ROOT)\src` directory while also passing the additional argument `--include-source` to the `dotnet pack` command.

    ## Example 4

        BuildTasks:
        - DotNetPack:
            Path:
            - DotNetCoreSolution.sln
            SdkVersion: 2.*

    Demonstrates creating a NuGet package using the latest `2.*` version of the .NET Core SDK.
    #>
    [CmdletBinding()]
    [Whiskey.Task("DotNetPack")]
    [Whiskey.RequiresTool('DotNet','DotNetPath',VersionParameterName='SdkVersion')]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Set-Item -Path 'env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE' -Value $true
    Set-Item -Path 'env:DOTNET_CLI_TELEMETRY_OPTOUT' -Value $true

    $dotnetExe = $TaskParameter['DotNetPath']

    $projectPaths = ''
    if ($TaskParameter['Path'])
    {
        $projectPaths = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    }

    $symbols = $TaskParameter['Symbols'] | ConvertFrom-WhiskeyYamlScalar

    $verbosity = $TaskParameter['Verbosity']
    if (-not $verbosity -and $TaskContext.ByBuildServer)
    {
        $verbosity = 'detailed'
    }

    $dotnetArgs = & {
        '-p:PackageVersion={0}' -f $TaskContext.Version.SemVer1.ToString()
        '--configuration={0}' -f (Get-WhiskeyMSBuildConfiguration -Context $TaskContext)
        '--output={0}' -f $TaskContext.OutputDirectory
        '--no-build'
        '--no-dependencies'
        '--no-restore'

        if ($symbols)
        {
            '--include-symbols'
        }

        if ($verbosity)
        {
            '--verbosity={0}' -f $verbosity
        }

        $TaskParameter['Argument']
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe command path:   {0}' -f $dotnetExe)
    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe SDK version:    {0}' -f (& $dotnetExe --version))
    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe pack arguments: {0}' -f ($dotnetArgs | Select-Object -First 1))
    $dotnetArgs | Select-Object -Skip 1 | ForEach-Object {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('                            {0}' -f $_)
    }
    Write-WhiskeyVerbose -Context $TaskContext -Message ''

    foreach($project in $projectPaths)
    {
        $fullCommandString = '{0} pack {1} {2}' -f $dotnetExe,($dotnetArgs -join ' '),$project
        Write-WhiskeyVerbose -Context $TaskContext -Message (' Executing: {0}' -f $fullCommandString)

        & $dotnetExe pack $dotnetArgs $project

        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('dotnet.exe failed with exit code ''{0}''' -f $LASTEXITCODE)
        }
    }
}
