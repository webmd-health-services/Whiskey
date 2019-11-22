
function Invoke-WhiskeyBuild
{
    <#
    .SYNOPSIS
    Runs a build.

    .DESCRIPTION
    The `Invoke-WhiskeyBuild` function runs a build as defined by your `whiskey.yml` file. Use the `New-WhiskeyContext` function to create a context object, then pass that context object to `Invoke-WhiskeyBuild`. `New-WhiskeyContext` takes the path to the `whiskey.yml` file you want to run:

        $context = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath 'whiskey.yml'
        Invoke-WhiskeyBuild -Context $context

    Builds can run in three modes: `Build`, `Clean`, and `Initialize`. The default behavior is `Build` mode.

    In `Build` mode, each task in the `Build` pipeline is run. If you're on a publishing branch, and being run on a build server, each task in the `Publish` pipeline is also run.

    In `Clean` mode, each task that supports clean mode is run. In this mode, tasks clean up any build artifacts they create. Tasks opt-in to this mode. If a task isn't cleaning up, it should be updated to support clean mode.

    In `Initialize` mode, each task that suppors initialize mode is run. In this mode, tasks download, install, and configure any tools or other dependencies needed. This mode is intended to be used by developers so they can get any tools needed to start developing without having to run an entire build, which may take a long time. Tasks opt-in to this mode. If a task uses an external tool or dependences, and they don't exist after running in `Initialize` mode, it should be updated to support `Initialize` mode.

    (Task authors should see the `about_Whiskey_Writing_Tasks` for information about how to opt-in to `Clean` and `Initialize` mode.)

    Your `whiskey.yml` file can contain multiple pipelines (see `about_Whiskey.yml` for information about `whiskey.yml syntax). Usually, there is a pipeline for each application you want to build. To build specific pipelines, pass the pipeline names to the `PipelineName` parameter. Just those pipeline will be run. The `Publish` pipeline will *not* run unless it is one of the names you pass to the `PipelineName` parameter.

    .LINK
    about_Whiskey.yml

    .LINK
    New-WhiskeyContext

    .LINK
    about_Whiskey_Writing_Tasks

    .EXAMPLE
    Invoke-WhiskeyBuild -Context $context

    Demonstrates how to run a complete build. In this example, the `Build` pipeline is run, and, if running on a build server and on a publishing branch, the `Publish` pipeline is run.

    .EXAMPLE
    Invoke-WhiskeyBuild -Context $context -Clean

    Demonstrates how to run a build in `Clean` mode. In this example, each task in the `Build` and `Publish` pipelines that support `Clean` mode is run so they can delete any build output, downloaded depedencies, etc.

    .EXAMPLE
    Invoke-WhiskeyBuild -Context $context -Initialize

    Demonstrates how to run a build in `Initialize` mode. In this example, each task in the `Build` and `Publish` pipelines that supports `Initialize` mode is run so they can download/install/configure any tools or dependencies.

    .EXAMPLE
    Invoke-WhiskeyBuild -Context $context -PipelineName 'App1','App2'

    Demonstrates how to run specific pipelines. In this example, all the tasks in the `App1` and `App2` pipelines are run. See `about_Whiskey.yml` for information about how to define pipelines.
    #>
    [CmdletBinding(DefaultParameterSetName='Build')]
    param(
        [Parameter(Mandatory)]
        # The context for the build. Use `New-WhiskeyContext` to create context objects.
        [Whiskey.Context]$Context,

        # The name(s) of any pipelines to run. Default behavior is to run the `Build` pipeline and, if on a publishing branch, the `Publish` pipeline.
        #
        # If you pass a value to this parameter, the `Publish` pipeline is *not* run implicitly. You must pass its name to run it.
        [String[]]$PipelineName,

        [Parameter(Mandatory,ParameterSetName='Clean')]
        # Runs the build in clean mode. In clean mode, tasks delete any artifacts they create, including downloaded tools and dependencies. This is opt-in, so if a task is not deleting its artifacts, it needs to be updated to support clean mode.
        [switch]$Clean,

        [Parameter(Mandatory,ParameterSetName='Initialize')]
        # Runs the build in initialize mode. In initialize mode, tasks download/install/configure any tools/dependencies they use/need during the build. Initialize mode is intended to be used by developers so that any tools/dependencies they need can be downloaded/installe/configured without needing to run an entire build, which can sometimes take a long time.
        [switch]$Initialize
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $PSBoundParameters.ContainsKey('InformationAction') )
    {
        # Whiskey logs to the information stream so make sure it is enabled. Unless the user wants it off.
        $InformationPreference = 'Continue'
    }

    $Context.StartedAt = $script:buildStartedAt = Get-Date

    # If there are older versions of the PackageManagement and/or PowerShellGet
    # modules available on this system, the modules that ship with Whiskey will use
    # those global versions instead of the versions we load from inside Whiskey. So,
    # we have to put the ones that ship with Whiskey first. See
    # https://github.com/PowerShell/PowerShellGet/issues/446 .
    $originalPSModulesPath = $env:PSModulePath
    $env:PSModulePath = '{0};{1}' -f (Join-Path -Path $Context.BuildRoot -ChildPath $powerShellModulesDirectoryName),$env:PSModulePath

    Set-WhiskeyBuildStatus -Context $Context -Status Started

    $succeeded = $false
    Push-Location -Path $Context.BuildRoot
    try
    {
        $Context.RunMode = $PSCmdlet.ParameterSetName

        if( $PipelineName )
        {
            foreach( $name in $PipelineName )
            {
                Invoke-WhiskeyPipeline -Context $Context -Name $name
            }
        }
        else
        {
            $config = $Context.Configuration

            $buildPipelineName = 'Build'
            if( $config.ContainsKey('BuildTasks') )
            {
                $buildPipelineName = 'BuildTasks'
            }

            Invoke-WhiskeyPipeline -Context $Context -Name $buildPipelineName

            $publishPipelineName = 'Publish'
            if( $config.ContainsKey('PublishTasks') )
            {
                $publishPipelineName = 'PublishTasks'
            }

            Write-WhiskeyVerbose -Context $Context -Message ('Publish?           {0}' -f $Context.Publish)
            Write-WhiskeyVerbose -Context $Context -Message ('Publish Pipeline?  {0}' -f $config.ContainsKey($publishPipelineName))
            if( $Context.Publish -and $config.ContainsKey($publishPipelineName) )
            {
                Invoke-WhiskeyPipeline -Context $Context -Name $publishPipelineName
            }
        }

        $succeeded = $true
    }
    finally
    {
        if( $Clean )
        {
            Remove-Item -path $Context.OutputDirectory -Recurse -Force | Out-String | Write-WhiskeyVerbose -Context $Context
        }
        Pop-Location

        $status = 'Failed'
        if( $succeeded )
        {
            $status = 'Completed'
        }
        Set-WhiskeyBuildStatus -Context $Context -Status $status

        $env:PSModulePath = $originalPSModulesPath
    }

    # There are some errors (strict mode validation failures, command not found errors, etc.) that stop a build, but 
    # even though ErrorActionPreference is Stop, it doesn't stop the current process, which is what causes a build to 
    # fail the build. If we get here, and the build didn't succeed, we've encountered one of those errors. Throw a 
    # guaranteed terminating error.
    if( -not $succeeded )
    {
        Write-Error -Message ('Build failed. See previous error output for more information.') -ErrorAction Stop
    }
}
