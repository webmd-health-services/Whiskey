
function Invoke-WhiskeyDotNetBuild
{
    <#
    .SYNOPSIS
    Builds .NET Core SDK projects.

    .DESCRIPTION
    The `DotNetBuild` tasks runs the `dotnet.exe build` command for building .NET projects targeting .NET Core and .NET Standard. Pass a list of solutions files or .NET Core project files to the `Path` property. If no files are provided to `Path`, then the .NET Core SDK will search for any solution or project files in the working directory and build those. If the `dotnet.exe build` command returns a non-zero exit code the build will fail.

    # Properties

    * `Argument`: a list of additional arguments to pass to the `dotnet.exe build` command.
    * `Path`: a list of paths to .NET Core solution or project files to build. If not specified, any solution or project files in the task working directory will be built.
    * `OutputDirectory`: the directory where assemblies should be compiled to. The default is the location specified in each project file.
    * `SdkVersion`: the version of the .NET Core SDK to use to build the project. Supports wildcard values. If not specified, the task will look for the SDK version from the `global.json` file if it is found in the task working directory or the Whiskey build root. If no SDK version can be located, the task will default to using the SDK version that comes with the latest LTS release of the .NET Core runtime. Whiskey will *always* update the SDK version property in the `global.json` file with the SDK version that task is running with. If no `global.json` file exists, one will be created in the Whiskey build root.
    * `Verbosity`: sets the verbosity level of dotnet.exe's output. For developers, the default is dotnet.exe's default verbosity. On build servers, the default is `detailed`. Allowed values are `q[uiet]`, `m[inimal]`, `n[ormal]`, `d[etailed]`, and `diag[nostic]`.

    # Examples

    ## Example 1

        BuildTasks:
        - DotNetBuild:
            Path:
            - DotNetCoreSolution.sln

    Demonstrates building the DotNetCoreSolution.sln file with the `dotnet build` command.

    ## Example 2

        BuildTasks:
        - DotNetBuild:
            Path:
            - DotNetCoreSolution.sln
            Verbosity: normal
            OutputDirectory: bin

    Demonstrates build a solution file with normal verbosity and compiling the assemblies to the '$(WHISKEY_BUILD_ROOT)\bin' directory.

    ## Example 3

        BuildTasks:
        - DotNetBuild:
            Path:
            - src\DotNetStandardLibrary.csproj
            - src\DotNetCoreApp.csproj
            Argument:
            - --no-dependencies

    Demonstrates building multiple .NET Core csproj files with an additional argument, `--no-dependencies`, passed to the `dotnet build` command.

    ## Example 4

        BuildTasks:
        - DotNetBuild:
            Path:
            - DotNetCoreSolution.sln
            SdkVersion: 2.*

    Demonstrates building a .NET Core solution with the latest `2.*` version of the .NET Core SDK.
    #>
    [CmdletBinding()]
    [Whiskey.Task("DotNetBuild")]
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

    $verbosity = $TaskParameter['Verbosity']
    if (-not $verbosity -and $TaskContext.ByBuildServer)
    {
        $verbosity = 'detailed'
    }

    $outputDirectory = $TaskParameter['OutputDirectory']
    if ($outputDirectory)
    {
        $outputDirectory = $outputDirectory | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'OutputDirectory' -Force
    }

    $dotnetArgs = & {
        '--configuration={0}' -f (Get-WhiskeyMSBuildConfiguration -Context $TaskContext)
        '-p:Version={0}'      -f $TaskContext.Version.SemVer1.ToString()

        if ($verbosity)
        {
            '--verbosity={0}' -f $verbosity
        }

        if ($outputDirectory)
        {
            '--output={0}' -f $outputDirectory
        }

        $TaskParameter['Argument']
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe command path:    {0}' -f $dotnetExe)
    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe SDK version:     {0}' -f (& $dotnetExe --version))
    Write-WhiskeyVerbose -Context $TaskContext -Message     (' dotnet.exe build arguments: {0}' -f ($dotnetArgs | Select-Object -First 1))
    $dotnetArgs | Select-Object -Skip 1 | ForEach-Object {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('                             {0}' -f $_)
    }
    Write-WhiskeyVerbose -Context $TaskContext -Message ''

    foreach($project in $projectPaths)
    {
        $fullCommandString = '{0} build {1} {2}' -f $dotnetExe,($dotnetArgs -join ' '),$project
        Write-WhiskeyVerbose -Context $TaskContext -Message (' Executing: {0}' -f $fullCommandString)

        & $dotnetExe build $dotnetArgs $project

        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('dotnet.exe failed with exit code ''{0}''' -f $LASTEXITCODE)
        }
    }
}
