
function Invoke-WhsCIBuild
{
    <#
    .SYNOPSIS
    Runs a build using settings from a `whsbuild.yml` file.

    .DESCRIPTION
    The `Invoke-WhsCIBuild` function runs a build based on the settings from a `whsbuild.yml` file. A minimal `whsbuild.yml` file should contain a `BuildTasks` element that is a list of the build tasks to perform. `Invoke-WhsCIBuild` supports the following tasks:
    
    * MSBuild
    * Node
    * NuGetPack
    * NUnit2
    * Pester2
    * PowerShell
    * WhsAppPackage
    
    Each task's elements are defined below.
    
    All paths used by a task must be relative to the `whsbuild.yml` file. Absolute paths will be rejected. Wildcards are allowed.
    
    All output from tasks (test reports, packages, etc.) are put in a directory named `.output` in the same directory as the `whsbuild.yml` file. This directory is removed and re-created every build. 
    
    You may also specify the semantic version of your application via a `Version` element.
    
    When run under a build server, the build status is reported to Bitbucket Server, which you can see on the repository's commits tab on the branch being built or on the branches tab in the Bitbucket Server web interface.
    
    When a build fails, `Invoke-WhsCIBuild` throws a terminating error. If `Invoke-WhsCIBuild` returns, you can assume a build passed.
    
    This function doesn't return anything useful, so don't try to capture output. We reserve the right to change what gets output at anytime.
    
    ## MSBuild
    
    The MSBuild task is used to build .NET projects with MSBuild from the version of .NET 4 that is installed. Items are built by running the `clean` and `build` target against each file. The task should contain a `Path` element that is a list of projects, solutions, or other files to build.  The build fails if any MSBuild target fails. If your `whsbuild.yml` file defines a `Version` element and the build is running under a build server, all AssemblyInfo.cs files under each path is updated with appropriate `AssemblyVersion`, `AssemblyFileVersion`, and `AssemblyInformationalVersion` attributes. The `AssemblyInformationalVersion` attribute will contain the full semantic version from `whsbuild.yml` plus some build metadata: the build server's build number, the Git branch, and the Git commit ID.
    
        Version: 1.3.2-rc.1
        BuildTasks:
        - MSBuild:
            Path: 
            - MySolution.sln
            - MyOtherSolution.sln

    ## Node

    The Node task is used to run Node.js builds. It runs npm scripts, e.g. `npm run <scripts>`. If any scripts fails, the build fails. The Node task also:
    
    * runs `npm install` before running any scripts
    * scans for security vulnerabilities using NSP, the Node Security Platform, and fails the build if any are found
    * generates a report on each dependency's licenses
    * removes developer dependencies from node_modules directory (i.e. runs the `npm prune` command) (this only happens when running under a build server)

    You are required to specify what version of Node your application uses in a package.json file. The version of Node is given in the engines field. See https://docs.npmjs.com/files/package.json#engines for more infomration.

        BuildTasks:
        - Node:
            NpmScripts:
            - build
            - test

    By default, your `package.json` is expected to be in your repository root, next to your `whsbuild.yml` file. If your application is in a sub-directory in your repository, use the `WorkingDirectory` element to specify the relative path to that directory, e.g.

        BuildTasks:
        - Node:
            NpmScripts: build
            WorkingDirectory: app

    In the above example, the Node.js application is in the `app` directory. All build commands will be run in that directory. 

    
    ## NuGetPack
    
    The NuGetPack task creates NuGet package from a `.csproj` or `.nuspec` file. It runs the `nuget.exe pack` command. The task should have a `Path` element that is a list of paths to run the task against. Each path is packaged separately. The build fails if no packages are created.
    
        BuildTasks:
        - NuGetPack:
            Path:
            - MyProject.csproj
            - MyNuspec.csproj
            
    ## NUnit2
    
    The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\packages`). The task should have a `Path` list which should be a list of assemblies whose tests to run. The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).
    
        BuildTasks:
        - NUnit2:
            Path:
            - Assembly.dll
            - OtherAssembly.dll
    
    ## Pester3
    
    The Pester3 task runs Pester tests using Pester 3. The latest version of Pester 3 is downloaded from the PowerShell Gallery for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\Modules`). The task should have a `Path` list which should be a list of Pester test files or directories containing Pester tests. (The paths are passed to `Invoke-Pester` function's `Script` parameter.) The build will fail if any of the tests fail.
    
        BuildTasks:
        - Pester3:
            Path:
            - My.Tests.ps1
            - Tests
            
    ## PowerShell
    
    The PowerShell task runs PowerShell scripts. The task should have a `Path` list which is a list of scripts to run. The build fails if any script exits with a non-zero exit code. Scripts are executed in the current working directory. Specify an explicit working directory with a `WorkingDirectory` element.
    
        BuildTasks:
        - PowerShell:
            Path:
            - myscript.ps1
            - myotherscript.ps1
            WorkingDirectory: bin
            
    ## WhsAppPackage
    
    The WhsAppPackage task creates a WHS application deployment package. When run on the build server, under a develop, release, or master branch it also uploads the package to ProGet and starts a deploy in BuildMaster. This package is saved in our artifact repository, deployed to servers, and installed. This task has the following elements:
    
    * `Path`: mandatory; the directories and files to include in the package. They will be added to the root of the package using the item's name.
    * `Name`: mandatory; the name of the package. Usually, this is the name of your application.
    * `Description`: mandatory; a description of your application.
    * `Include`: mandatory; a whitelist of file names to include in the package. Wildcards supported. This must have at least one item. Only files that match an item in this list will be in the package. All other files are excluded.
    * `Exclude`: optional; an extra filter against `Include` any file or directory included by `Include` that matches an item in `Exclude` is ommitted from the package.
 
    The version of the package is taken from the `Version` element in the `whsbuild.yml` file.
    
    The task excludes `.hg`, `.git`, and `obj` directories for you.
    
        Version: 1.5.5
        BuildTasks:
        - WhsAppPackage:
            Name: MyApplication
            Description: The MyApplication is responsible for all the cool things.
            Include: 
            - *.aspx
            - *.css
            - *.js
            Exclude:
            - test
            - backdoor
            
    
    .EXAMPLE
    Invoke-WhsCIBuild -ConfigurationPath 'whsbuild.yml' -BuildConfiguration 'Debug'
    
    Demonstrates the simplest way to call `Invoke-WhsCIBuild`. In this case, all the tasks in `whsbuild.yml` are run. If any code is compiled, it is compiled with the `Debug` configuration.
    
    .EXAMPLE
    Invoke-WhsCIBuild -ConfigurationPath 'whsbuild.yml' -BuildConfiguration 'Release' --BBServerCredential $credential -BBServerUri $bbserverUri
    
    Demonstrates how to get `Invoke-WhsCIBuild` build status to Bitbucket Server, when run under a build server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context for the build. Use `New-WhsCIContext` to create context objects.
        $Context,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $Context.ByBuildServer )
    {
        Set-BBServerCommitBuildStatus -Connection $Context.BBServerConnection -Status InProgress
    }

    $succeeded = $false
    Push-Location -Path $Context.BuildRoot
    try
    {
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve

        Write-Verbose -Message ('Building version {0}' -f $Context.Version.SemVer2)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer2NoBuildMetadata)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.Version)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer1)

        $config = $Context.Configuration

        if( $config.ContainsKey('BuildTasks') )
        {
            # Tasks that should be called with the WhatIf switch when run by developers
            # This makes builds go a little faster.
            $developerWhatIfTasks = @{
                                        'AppPackage' = $true;
                                        'NodeAppPackage' = $true;
                                     }

            $taskIdx = -1
            if( $config['BuildTasks'] -is [string] )
            {
                Write-Warning -Message ('It looks like ''{0}'' doesn''t define any build tasks.' -f $Context.ConfigurationPath)
                $config['BuildTasks'] = @()
            }

            $knownTasks = Get-WhiskeyTasks
            foreach( $task in $config['BuildTasks'] )
            {
                $taskIdx++
                if( $task -is [string] )
                {
                    $taskName = $task
                    $task = @{ }
                }
                elseif( $task -is [hashtable] )
                {
                    $taskName = $task.Keys | Select-Object -First 1
                    $task = $task[$taskName]
                    if( -not $task )
                    {
                        $task = @{ }
                    }
                }
                else
                {
                    continue
                }

                $Context.TaskName = $taskName
                $Context.TaskIndex = $taskIdx

                $errorPrefix = '{0}: BuildTasks[{1}]: {2}: ' -f $Context.ConfigurationPath,$taskIdx,$taskName

                $errors = @()
                $pathIdx = -1


                if( -not $knownTasks.Contains($taskName) )
                {
                    #I'm guessing we no longer need this code because we are going to be supporting a wider variety of tasks. Thus perhaps a different message will be necessary here.
                    $knownTasks = $knownTasks.Keys | Sort-Object
                    throw ('{0}: BuildTasks[{1}]: ''{2}'' task does not exist. Supported tasks are:{3} * {4}' -f $Context.ConfigurationPath,$taskIdx,$taskName,[Environment]::NewLine,($knownTasks -join ('{0} * ' -f [Environment]::NewLine)))
                }

                $taskFunctionName = $knownTasks[$taskName]

                $optionalParams = @{ }
                if( $Context.ByDeveloper -and $developerWhatIfTasks.ContainsKey($taskName) )
                {
                    $optionalParams['WhatIf'] = $True
                }
                if ( $Clean )
                {
                    $optionalParams['Clean'] = $True
                }

                Write-Verbose -Message ('{0}' -f $taskName)
                $startedAt = Get-Date
                #I feel like this is missing a piece, because the current way that WhsCI tasks are named, they will never be run by this logic.
                & $taskFunctionName -TaskContext $context -TaskParameter $task @optionalParams
                $endedAt = Get-Date
                $duration = $endedAt - $startedAt
                Write-Verbose ('{0} COMPLETED in {1}' -f $taskName,$duration)
                Write-Verbose ('')

            }
            New-WhsCIBuildMasterPackage -TaskContext $Context
        }

        $succeeded = $true
    }
    finally
    {
        if( $Clean )
        {
            Remove-Item -path $Context.OutputDirectory -Recurse -Force | Out-String | Write-Verbose
        }
        Pop-Location

        if( $Context.ByBuildServer )
        {
            $status = 'Failed'
            if( $succeeded )
            {
                $status = 'Successful'
                Publish-WhsCITag -TaskContext $Context 
            }

            Set-BBServerCommitBuildStatus -Connection $Context.BBServerConnection -Status $status
        }
    }
}
