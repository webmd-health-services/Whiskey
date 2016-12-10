
function Invoke-WhsCIBuild
{
    <#
    .SYNOPSIS
    Runs a build using settings from a `whsbuild.yml` file.

    .DESCRIPTION
    The `Invoke-WhsCIBuild` function runs a build based on the settings from a `whsbuild.yml` file. A minimal `whsbuild.yml` file should contain a `BuildTasks` element that is a list of the build tasks to perform. `Invoke-WhsCIBuild` supports the following tasks:
    
    * MSBuild
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
    
    The MSBuild task is used to build .NET projects with MSBuild from the version of .NET 4 that is installed. Items are built by running the `clean` and `build` target against each file. The task should contain a `Paths` element that is a list of projects, solutions, or other files to build.  The build fails if any MSBuild target fails. If your `whsbuild.yml` file defines a `Version` element and the build is running under a build server, all AssemblyInfo.cs files under each path is updated with appropriate `AssemblyVersion`, `AssemblyFileVersion`, and `AssemblyInformationalVersion` attributes. The `AssemblyInformationalVersion` attribute will contain the full semantic version from `whsbuild.yml` plus some build metadata: the build server's build number, the Git branch, and the Git commit ID.
    
        Version: 1.3.2-rc.1
        BuildTasks:
        - MSBuild:
            Paths: 
            - MySolution.sln
            - MyOtherSolution.sln
    
    ## NuGetPack
    
    The NuGetPack task creates NuGet package from a `.csproj` or `.nuspec` file. It runs the `nuget.exe pack` command. The task should have a `Path` element that is a list of paths to run the task against. Each path is packaged separately. The build fails if no packages are created.
    
        BuildTasks:
        - NuGetPack:
            Paths:
            - MyProject.csproj
            - MyNuspec.csproj
            
    ## NUnit2
    
    The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\packages`). The task should have a `Paths` list which should be a list of assemblies whose tests to run. The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).
    
        BuildTasks:
        - NUnit2:
            Paths:
            - Assembly.dll
            - OtherAssembly.dll
    
    ## Pester3
    
    The Pester3 task runs Pester tests using Pester 3. The latest version of Pester 3 is downloaded from the PowerShell Gallery for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\Modules`). The task should have a `Paths` list which should be a list of Pester test files or directories containing Pester tests. (The paths are passed to `Invoke-Pester` function's `Script` parameter.) The build will fail if any of the tests fail.
    
        BuildTasks:
        - Pester3:
            Paths:
            - My.Tests.ps1
            - Tests
            
    ## PowerShell
    
    The PowerShell task runs PowerShell scripts. The task should have a `Paths` list which is a list of script to run. The build fails if any script exits with a non-zero exit code.
    
        BuildTasks:
        - PowerShell:
            Paths:
            - myscript.ps1
            - myotherscript.ps1
            
    ## WhsAppPackage
    
    The WhsAppPackage task creates a WHS application deployment package. This package is saved in our artifact repository, deployed to servers, and installed. This task has the following elements:
    
    * `Paths`: mandatory; the directories and files to include in the package. They will be added to the root of the package using the item's name.
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
    Invoke-WhsCIBuild -ConfigurationPath 'whsbuild.yml' -BuildConfiguration 'Release' -BBServerCredential $credential -BBServerUri $bbserverUri
    
    Demonstrates how to get `Invoke-WhsCIBuild` build status to Bitbucket Server, when run under a build server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the `whsbuild.yml` file to use.
        $ConfigurationPath,

        [Parameter(Mandatory=$true)]
        [string]
        # The build configuration to use if you're compiling code, e.g. `Debug`, `Release`.
        $BuildConfiguration,

        [pscredential]
        # The connection to use to contact Bitbucket Server. Required if running under a build server.
        $BBServerCredential,

        [string]
        # The URI to your Bitbucket Server installation.
        $BBServerUri,

        [string]
        # The place where downloaded tools should be saved. The default is `$env:LOCALAPPDATA\WebMD Health Services\WhsCI`.
        $DownloadRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    function Write-CommandOutput
    {
        param(
            [Parameter(ValueFromPipeline=$true)]
            [string]
            $InputObject
        )

        process
        {
            if( $InputObject -match '^WARNING\b' )
            {
                $InputObject | Write-Warning 
            }
            elseif( $InputObject -match '^ERROR\b' )
            {
                $InputObject | Write-Error
            }
            else
            {
                $InputObject | Write-Host
            }
        }
    }

    if( -not ($DownloadRoot) )
    {
        $downloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    }

    $runningUnderBuildServer = Test-Path -Path 'env:JENKINS_URL'

    if( $runningUnderBuildServer )
    {
        $conn = New-BBServerConnection -Credential $BBServerCredential -Uri $BBServerUri
        Set-BBServerCommitBuildStatus -Connection $conn -Status InProgress
    }

    $succeeded = $false
    try
    {
        $ConfigurationPath = Resolve-Path -LiteralPath $ConfigurationPath
        if( -not $ConfigurationPath )
        {
            throw ('Configuration file path ''{0}'' does not exist.' -f $PSBoundParameters['ConfigurationPath'])
        }

        # Do the build
        $config = Get-Content -Path $ConfigurationPath -Raw | ConvertFrom-Yaml
        $root = Split-Path -Path $ConfigurationPath -Parent
        $outputRoot = Join-Path -Path $root -ChildPath '.output'
        if( (Test-Path -Path $outputRoot -PathType Container) )
        {
            Remove-Item -Path $outputRoot -Force -Recurse
        }

        if( -not (Test-Path -Path $outputRoot -PathType Container) )
        {
            New-Item -Path $outputRoot -ItemType 'Directory' | Out-String | Write-Verbose
        }

        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve

        [SemVersion.SemanticVersion]$semVersion = $null
        [version]$version = $null
        $nugetVersion = $null
        if( ($config.ContainsKey('Version')) )
        {
            $rawVersion = $config['Version']
            if( $rawVersion -is [datetime] )
            {
                $patch = $rawVersion.Year
                if( $patch -ge 2000 )
                {
                    $patch -= 2000
                }
                elseif( $patch -ge 1900 )
                {
                    $patch -= 1900
                }
                $rawVersion = '{0}.{1}.{2}' -f $rawVersion.Month,$rawVersion.Day,$patch
            }
            if( -not ([SemVersion.SemanticVersion]::TryParse($rawVersion,[ref]$semVersion)) )
            {
                throw ('{0}: Version: ''{1}'' is not a valid semantic version. Please see http://semver.org for semantic versioning documentation.' -f $ConfigurationPath,$config.Version)
                return $false
            }

            $version = '{0}.{1}.{2}' -f $semVersion.Major,$semVersion.Minor,$semVersion.Patch
            $nugetVersion = $semVersion
            if( $runningUnderBuildServer )
            {
                $buildID = (Get-Item -Path 'env:BUILD_ID').Value
                $branch = (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
                $commitID = 'fubarsnafu' # (Get-Item -Path 'env:GIT_COMMIT').Value.Substring(0,7)
                $buildInfo = '{0}.{1}.{2}' -f $buildID,$branch,$commitID
                $semVersion = New-Object -TypeName 'SemVersion.SemanticVersion' ($semVersion.Major,$semVersion.Minor,$semVersion.Patch,$semVersion.Prerelease,$buildInfo)
            }
        }

        if( $config.ContainsKey('BuildTasks') )
        {
            $taskIdx = -1
            foreach( $task in $config['BuildTasks'] )
            {
                $taskIdx++
                $taskName = $task.Keys | Select-Object -First 1
                $task = $task[$taskName]

                $errorPrefix = '{0}: BuildTasks[{1}]: {2}: ' -f $ConfigurationPath,$taskIdx,$taskName

                if( $task -isnot [hashtable] )
                {
                    throw ('{0}: BuildTasks[{1}]: {2}: ''Path'' property not found. This property is mandatory for all tasks. It can be a single path or an array/list of paths.' -f $ConfigurationPath,$taskIdx,$taskName)
                }

                $errors = @()
                $taskPaths = New-Object 'Collections.Generic.List[string]' 
                $pathIdx = -1
                if( -not $task.ContainsKey('Path') )
                {
                    throw ('{0}: BuildTasks[{1}]: {2}: ''Path'' property not found. This property is mandatory for all tasks. It can be a single path or an array/list of paths.' -f $ConfigurationPath,$taskIdx,$taskName)
                }

                $foundInvalidTaskPath = $false
                foreach( $taskPath in $task.Path )
                {
                    $pathIdx++
                    if( [IO.Path]::IsPathRooted($taskPath) )
                    {
                        Write-Error -Message ('{0}: BuildTasks[{1}]: {2}: Path[{3}] ''{4}'' is absolute but must be relative to the whsbuild.yml file.' -f $ConfigurationPath,$taskIdx,$taskName,$pathIdx,$taskPath)
                        $foundInvalidTaskPath = $true
                        continue
                    }

                    $taskPath = Join-Path -Path $root -ChildPath $taskPath
                    if( -not (Test-Path -Path $taskPath) )
                    {
                        Write-Error -Message ('{0}: BuildTasks[{1}]: {2}: Path[{3}] ''{4}'' does not exist.' -f $ConfigurationPath,$taskIdx,$taskName,$pathIdx,$taskPath)
                        $foundInvalidTaskPath = $true
                    }

                    Resolve-Path -Path $taskPath | ForEach-Object { $taskPaths.Add($_.ProviderPath) }
                }

                if( $foundInvalidTaskPath )
                {
                    throw ('{0}: BuildTasks[{1}]: {2}: One or more of the task''s paths do not exist or are absolute.' -f $ConfigurationPath,$taskIdx,$taskName,$pathIdx,$taskPath)
                }

                switch( $taskName )
                {
                    'MSBuild' {
                        foreach( $projectPath in $taskPaths )
                        {
                            $errors = $null
                            if( $projectPath -like '*.sln' )
                            {
                                & $nugetPath restore $projectPath | Write-CommandOutput
                            }

                            if( $version -and $runningUnderBuildServer )
                            {
                                $projectPath | 
                                    Split-Path | 
                                    Get-ChildItem -Filter 'AssemblyInfo.cs' -Recurse | 
                                    ForEach-Object {
                                        $assemblyInfo = $_
                                        $assemblyInfoPath = $assemblyInfo.FullName
                                        $newContent = Get-Content -Path $assemblyInfoPath | Where-Object { $_ -notmatch '\bAssembly(File|Informational)?Version\b' }
                                        $newContent | Set-Content -Path $assemblyInfoPath
                                        $informationalVersion = '{0}' -f $semVersion
    @"
[assembly: System.Reflection.AssemblyVersion("{0}")]
[assembly: System.Reflection.AssemblyFileVersion("{0}")]
[assembly: System.Reflection.AssemblyInformationalVersion("{1}")]
"@ -f $version,$informationalVersion | Add-Content -Path $assemblyInfoPath
                                    }
                            }
                            Invoke-MSBuild -Path $projectPath -Target 'clean','build' -Property ('Configuration={0}' -f $BuildConfiguration) -ErrorVariable 'errors'
                            if( $errors )
                            {
                                throw ('Building ''{0}'' MSBuild project''s ''clean'',''build'' targets with {1} configuration failed.' -f $projectPath,$BuildConfiguration)
                            }
                        }
                    }

                    'NuGetPack' {
                        foreach( $path in $taskPaths )
                        {
                            $preNupkgCount = Get-ChildItem -Path $outputRoot -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
                            $versionArgs = @()
                            if( $nugetVersion )
                            {
                                $versionArgs = @( '-Version', $nugetVersion )
                            }
                            & $nugetPath pack $versionArgs -OutputDirectory $outputRoot -Symbols -Properties ('Configuration={0}' -f $BuildConfiguration) $path | Write-CommandOutput
                            $postNupkgCount = Get-ChildItem -Path $outputRoot -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
                            if( $postNupkgCount -eq $preNupkgCount )
                            {
                                throw ('NuGet pack command failed. No new .nupkg files found in ''{0}''.' -f $outputRoot)
                            }
                        }
                    }

                    'NUnit2' {
                        $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'packages'
                        $nunitRoot = Join-Path -Path $packagesRoot -ChildPath 'NUnit.Runners.2.6.4'
                        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
                        {
                            & $nugetPath install 'NUnit.Runners' -version '2.6.4' -OutputDirectory $packagesRoot
                        }
                        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
                        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'

                        $binRoots = $taskPaths | Group-Object -Property { Split-Path -Path $_ -Parent } 
                        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve

                        Push-Location -Path $root
                        try
                        {
                            $assemblyNames = $taskPaths | ForEach-Object { $_ -replace ([regex]::Escape($root)),'.' }
                            $testResultPath = Join-Path -Path $outputRoot -ChildPath ('nunit2-{0:00}.xml' -f $taskIdx)
                            & $nunitConsolePath $assemblyNames /noshadow /framework=4.0 /domain=Single /labels ('/xml={0}' -f $testResultPath)
                            if( $LastExitCode )
                            {
                                throw ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
                            }
                        }
                        finally
                        {
                            Pop-Location
                        }
                    }

                    'Pester3' {
                        $moduleDownloadRoot = Join-Path -Path $DownloadRoot -ChildPath 'Modules'
                        $pesterRoot = Join-Path -Path $moduleDownloadRoot -ChildPath 'Pester'
                        $downloadPester = $false
                        if( (Test-Path -Path $pesterRoot -PathType Container) )
                        {
                            $pesterInfo = Get-Module -Name $pesterRoot -ListAvailable
                            if( $pesterInfo.Version -lt [version]'3.0' -or $pesterInfo.Version -ge '4.0' )
                            {
                                $downloadPester = $true
                            }
                        }
                        else
                        {
                            $downloadPester = $true
                        }

                        if( $downloadPester )
                        {
                            if( -not (Test-Path -Path $moduleDownloadRoot -PathType Container) )
                            {
                                New-Item -Path $moduleDownloadRoot -ItemType 'Directory'
                            }
                            Save-Module -Name 'Pester' `
                                        -MinimumVersion '3.0' `
                                        -MaximumVersion ('3.{0}' -f [int16]::MaxValue) `
                                        -Repository 'PSGallery' `
                                        -Path $moduleDownloadRoot
                        }

                        # We do this in the background so we can test this with Pester. Pester tests calling Pester tests. Madness!
                        $result = Start-Job -ScriptBlock {
                            $myScriptRoot = $using:PSScriptRoot
                            $script = $using:taskpaths
                            $outputRoot = $using:outputRoot
                            $taskIdx = $using:taskIdx
                            $pesterRoot = $using:pesterRoot

                            Import-Module -Name $pesterRoot
                            $outputFile = Join-Path -Path $outputRoot -ChildPath ('pester-{0:00}.xml' -f $taskIdx)
                            Invoke-Pester -Script $script -OutputFile $outputFile -OutputFormat LegacyNUnitXml -PassThru
                        } | Wait-Job | Receive-Job

                        if( $result.FailedCount )
                        {
                            throw ('Pester tests failed.')
                        }
                    }

                    'PowerShell' {
                        foreach( $scriptPath in $taskPaths )
                        {
                            & $scriptPath
                            if( $LastExitCode )
                            {
                                throw ('PowerShell script ''{0}'' failed, exiting with code {1}.' -F $scriptPath,$LastExitCode)
                            }
                        }
                    }

                    'WhsAppPackage' {
                        $excludeParam = @{}
                        foreach( $mandatoryName in @( 'Name', 'Description', 'Include' ) )
                        {
                            if( -not $task.ContainsKey($mandatoryName) )
                            {
                                throw ('{0}Element ''{1}'' is mandatory.' -f $errorPrefix,$mandatoryName)
                            }
                        }
                        if( $task['Exclude'] )
                        {
                            $excludeParam['Exclude'] = $task['Exclude']
                        }

                        New-WhsAppPackage -RepositoryRoot $root `
                                          -Name $task['Name'] `
                                          -Description $task['Description'] `
                                          -Version $nugetVersion `
                                          -Path $taskPaths `
                                          -Include $task['Include'] `
                                          @excludeParam
                    }

                    default {
                        $knownTasks = @( 'MSBuild','NuGetPack','NUNit2', 'Pester', 'PowerShell', 'WhsAppPackage' ) | Sort-Object
                        throw ('{0}: BuildTasks[{1}]: ''{2}'' task does not exist. Supported tasks are:{3} * {4}' -f $ConfigurationPath,$taskIdx,$taskName,[Environment]::NewLine,($knownTasks -join ('{0} * ' -f [Environment]::NewLine)))
                    }
                }
            }
        }

        $succeeded = $true
    }
    finally
    {
        if( $runningUnderBuildServer )
        {
            $status = 'Failed'
            if( $succeeded )
            {
                $status = 'Successful'
            }

            Set-BBServerCommitBuildStatus -Connection $conn -Status $status
        }
    }
}
