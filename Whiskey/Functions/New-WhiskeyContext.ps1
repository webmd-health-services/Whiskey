
function New-WhiskeyContext
{
    <#
    .SYNOPSIS
    Creates a context object to use when running builds.

    .DESCRIPTION
    The `New-WhiskeyContext` function creates a `Whiskey.Context` object used when running builds. It:

    * Reads in the whiskey.yml file containing the build you want to run.
    * Creates a ".output" directory in the same directory as your whiskey.yml file for storing build output, logs, results, temp files, etc.
    * Reads build metadata created by the current build server (if being run by a build server).
    * Sets the version number to "0.0.0".

    ## Whiskey.Context

    The `Whiskey.Context` object has the following properties. ***Do not use any property not defined below.*** Also, these properties are ***read-only***. If you write to them, Bad Things (tm) could happen.

    * `BuildMetadata`: a `Whiskey.BuildInfo` object representing build metadata provided by the build server.
    * `BuildRoot`: a `System.IO.DirectoryInfo` object representing the directory the YAML configuration file is in.
    * `ByBuildServer`: a flag indicating if the build is being run by a build server.
    * `ByDeveloper`: a flag indicating if the build is being run by a developer.
    * `Environment`: the environment the build is running in.
    * `OutputDirectory`: a `System.IO.DirectoryInfo` object representing the path to a directory where build output, reports, etc. should be saved. This directory is created for you.
    * `ShouldClean`: a flag indicating if the current build is running in clean mode.
    * `ShouldInitialize`: a flag indicating if the current build is running in initialize mode.
    * `Temp`: the temporary work directory for the current task.
    * `Version`: a `Whiskey.BuildVersion` object representing version being built (see below).

    Any other property is considered private and may be removed, renamed, and/or reimplemented at our discretion without notice.

    ## Whiskey.BuildInfo

    The `Whiskey.BuildInfo` object has the following properties.  ***Do not use any property not defined below.*** Also, these properties are ***read-only***. If you write to them, Bad Things (tm) could happen.

    * `BuildNumber`: the current build number. This comes from the build server. (If the build is being run by a developer, this is always "0".) It increments with every new build (or should). This number is unique only to the current build job.
    * `ScmBranch`: the branch name from which the current build is running.
    * `ScmCommitID`: the unique commit ID from which the current build is running. The commit ID distinguishes the current commit from all others in the source repository and is the same across copies of a repository.

    ## Whiskey.BuildVersion

    The `Whiskey.BuildVersion` object has the following properties.  ***Do not use any property not defined below.*** Also, these properties are ***read-only***. If you write to them, Bad Things (tm) could happen.

    * `SemVer2`: the version currently being built.
    * `Version`: a `System.Version` object for the current build. Only major, minor, and patch/build numbers will be filled in.
    * `SemVer1`: a semver version 1 compatible version of the current build.
    * `SemVer2NoBuildMetadata`: the current version without any build metadata.

    .EXAMPLE
    New-WhiskeyContext -Path '.\whiskey.yml'

    Demonstrates how to create a context for a developer build.
    #>
    [CmdletBinding()]
    [OutputType([Whiskey.Context])]
    param(
        [Parameter(Mandatory)]
        # The environment you're building in.
        [String]$Environment,

        [Parameter(Mandatory)]
        # The path to the `whiskey.yml` file that defines build settings and tasks.
        [String]$ConfigurationPath,

        # The place where downloaded tools should be cached. The default is the build root.
        [String]$DownloadRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $ConfigurationPath = Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Ignore
    if( -not $ConfigurationPath )
    {
        throw ('Configuration file path ''{0}'' does not exist.' -f $PSBoundParameters['ConfigurationPath'])
    }

    $config = Import-WhiskeyYaml -Path $ConfigurationPath

    if( $config.ContainsKey('Build') -and $config.ContainsKey('BuildTasks') )
    {
        throw ('{0}: The configuration file contains both "Build" and the deprecated "BuildTasks" pipelines. Move all your build tasks under "Build" and remove the "BuildTasks" pipeline.' -f $ConfigurationPath)
    }

    if( $config.ContainsKey('BuildTasks') )
    {
        Write-WhiskeyWarning ('{0}: The default "BuildTasks" pipeline has been renamed to "Build". Backwards compatibility with "BuildTasks" will be removed in the next major version of Whiskey. Rename your "BuildTasks" pipeline to "Build".' -f $ConfigurationPath)
    }

    if( $config.ContainsKey('Publish') -and $config.ContainsKey('PublishTasks') )
    {
        throw ('{0}: The configuration file contains both "Publish" and the deprecated "PublishTasks" pipelines. Move all your publish tasks under "Publish" and remove the "PublishTasks" pipeline.' -f $ConfigurationPath)
    }

    if( $config.ContainsKey('PublishTasks') )
    {
        Write-WhiskeyWarning ('{0}: The default "PublishTasks" pipeline has been renamed to "Publish". Backwards compatibility with "PublishTasks" will be removed in the next major version of Whiskey. Rename your "PublishTasks" pipeline to "Publish".' -f $ConfigurationPath)
    }

    $buildRoot = $ConfigurationPath | Split-Path
    if( -not $DownloadRoot )
    {
        $DownloadRoot = $buildRoot
    }

    [Whiskey.BuildInfo]$buildMetadata = Get-WhiskeyBuildMetadata
    $publish = $false
    $byBuildServer = $buildMetadata.IsBuildServer
    if( $byBuildServer )
    {
        $branch = $buildMetadata.ScmBranch

        if( $config.ContainsKey( 'PublishOn' ) )
        {
            Write-WhiskeyVerbose -Message ('PublishOn')
            foreach( $publishWildcard in $config['PublishOn'] )
            {
                $publish = $branch -like $publishWildcard
                if( $publish )
                {
                    Write-WhiskeyVerbose -Message ('           {0}    -like  {1}' -f $branch,$publishWildcard)
                    break
                }
                else
                {
                    Write-WhiskeyVerbose -Message ('           {0} -notlike  {1}' -f $branch,$publishWildcard)
                }
            }
        }
    }

    $outputDirectory = Join-Path -Path $buildRoot -ChildPath '.output'
    if( -not (Test-Path -Path $outputDirectory -PathType Container) )
    {
        New-Item -Path $outputDirectory -ItemType 'Directory' -Force | Out-Null
    }

    $context = New-WhiskeyContextObject
    $context.BuildRoot = $buildRoot
    $runBy = [Whiskey.RunBy]::Developer
    if( $byBuildServer )
    {
        $runBy = [Whiskey.RunBy]::BuildServer
    }
    $context.RunBy = $runBy
    $context.BuildMetadata = $buildMetadata
    $context.Configuration = $config
    $context.ConfigurationPath = $ConfigurationPath
    $context.DownloadRoot = $DownloadRoot
    $context.Environment = $Environment
    $context.OutputDirectory = $outputDirectory
    $context.Publish = $publish
    $context.RunMode = [Whiskey.RunMode]::Build

    if( $config['Variable'] )
    {
        Write-WhiskeyError -Message ('{0}: The "Variable" property is no longer supported. Use the `SetVariable` task instead. Move your `Variable` property (and values) into your `Build` pipeline as the first task. Rename `Variable` to `SetVariable`.' -f $ConfigurationPath) -ErrorAction Stop
    }

    $context.Version = New-WhiskeyVersionObject -SemVer '0.0.0'

    return $context
}

