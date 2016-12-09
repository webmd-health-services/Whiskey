
function Invoke-WhsCIBuild
{
    <#
    .SYNOPSIS
    Runs a build using settings from a `whsbuild.yml` file.

    .DESCRIPTION
    The `Invoke-WhsCIBuild` function runs a build based on the settings from a `whsbuild.yml` file.
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
        $BBServerUri
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
                $commitID = (Get-Item -Path 'env:GIT_COMMIT').Value.Substring(0,7)
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
                if( $task -isnot [hashtable] )
                {
                    throw -Message ('{0}: BuildTasks[{1}]: {2}: ''Path'' property not found. This property is mandatory for all tasks. It can be a single path or an array/list of paths.' -f $ConfigurationPath,$taskIdx,$taskName)
                }

                $errors = @()
                $taskPaths = New-Object 'Collections.Generic.List[string]' 
                $pathIdx = -1
                if( -not $task.ContainsKey('Path') )
                {
                    throw -Message ('{0}: BuildTasks[{1}]: {2}: ''Path'' property not found. This property is mandatory for all tasks. It can be a single path or an array/list of paths.' -f $ConfigurationPath,$taskIdx,$taskName)
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
                        $packagesRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\packages'
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

                    'Pester' {
                        #Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Pester')
                        $result = Invoke-Pester -Script $taskPaths -OutputXml (Join-Path -Path $outputRoot -ChildPath ('pester-{0:00}.xml' -f $taskIdx)) -PassThru
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

                    <#
                    'WhsAppPackage' {
                        $excludeParam = @{}
                        if( $task['Exclude'] )
                        {
                            $excludeParam = $task['Exclude']
                        }

                        New-WhsAppPackage -RepositoryRoot $root `
                                          -Name $task['Name'] `
                                          -Description $task['Description'] `
                                          -Version $nugetVersion `
                                          -Path $taskPaths `
                                          -Include $task['Include'] `
                                          @excludeParam
                    }
                    #>

                    default {
                        $knownTasks = @( 'MSBuild','NuGetPack','NUNit2', 'Pester', 'PowerShell' ) | Sort-Object
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
