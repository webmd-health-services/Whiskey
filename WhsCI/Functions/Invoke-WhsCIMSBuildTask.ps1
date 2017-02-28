function Invoke-WhsCIMSBuildTask
{
    <#
    .SYNOPSIS
    Invoke-WhsCIMSBuildTask builds .NET projects with MSBuild

    .DESCRIPTION
    The MSBuild task is used to build .NET projects with MSBuild from the version of .NET 4 that is installed. Items are built by running the `clean` and `build` target against each file. The TaskParameter should contain a `Path` element that is a list of projects, solutions, or other files to build.  
    
    The build fails if any MSBuild target fails. If your `whsbuild.yml` file defines a `Version` element and the build is running under a build server, all AssemblyInfo.cs files under each path is updated with appropriate `AssemblyVersion`, `AssemblyFileVersion`, and `AssemblyInformationalVersion` attributes. The `AssemblyInformationalVersion` attribute will contain the full semantic version from `whsbuild.yml` plus some build metadata: the build server's build number, the Git branch, and the Git commit ID.

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhsCIMSBuildTask -TaskContext $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to call the `WhsCIMSBuildTask`. In this case each path in the `Path` element in $TaskParameter relative to your whsbuild.yml file, will be built with MSBuild.exe given the build configuration contained in $TaskContext.

    #>
    [CmdletBinding()]
    param(
        [object]
        # The context this task is operating in. Use `New-WhsCIContext` to create context objects.
        $TaskContext,
        
        [hashtable]
        # The parameters/configuration to use to run the task. Should be a hashtable that contains the following item(s):
        # 
        # * `Path` (Mandatory): the relative paths to the files/directories to include in the build. Paths should be relative to the whsbuild.yml file they were taken from.
        $TaskParameter
    )
  
    Set-StrictMode -version 'latest'  

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

    #setup
    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
    
    # Make sure the Taskpath contains a Path parameter.
    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, relative to your whsbuild.yml file, to build with MSBuild.exe, e.g. 
        
        BuildTasks:
        - MSBuild:
            Path:
            - MySolution.sln
            - MyCsproj.csproj')
    }

    $path = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'
   
    #build
    foreach( $projectPath in $path )
    {
        
        $errors = $null
        if( $projectPath -like '*.sln' )
        {
            & $nugetPath restore $projectPath | Write-CommandOutput
        }

        if( (Test-WhsCIRunByBuildServer) )
        {
            $projectPath | 
                Split-Path | 
                Get-ChildItem -Filter 'AssemblyInfo.cs' -Recurse | 
                ForEach-Object {
                    $assemblyInfo = $_
                    $assemblyInfoPath = $assemblyInfo.FullName
                    $newContent = Get-Content -Path $assemblyInfoPath | Where-Object { $_ -notmatch '\bAssembly(File|Informational)?Version\b' }
                    $newContent | Set-Content -Path $assemblyInfoPath
    @"
[assembly: System.Reflection.AssemblyVersion("{0}")]
[assembly: System.Reflection.AssemblyFileVersion("{0}")]
[assembly: System.Reflection.AssemblyInformationalVersion("{1}")]
"@ -f $TaskContext.Version.Version,$TaskContext.Version | Add-Content -Path $assemblyInfoPath
                                    }
        }
        Invoke-MSBuild -Path $projectPath -Target 'clean','build' -Property ('Configuration={0}' -f $TaskContext.BuildConfiguration) -ErrorVariable 'errors'
        if( $errors )
        {
            throw ('Building ''{0}'' MSBuild project''s ''clean'',''build'' targets with {1} configuration failed.' -f $projectPath,$TaskContext.BuildConfiguration)
        }
    }
}