function Invoke-WhsCIMSBuildTask
{
    <#
    .SYNOPSIS
    Invoke-WhsCIMSBuildTask builds .NET projects with MSBuild

    .DESCRIPTION
    The MSBuild task is used to build .NET projects with MSBuild from the version of .NET 4 that is installed. Items are built by running the `clean` and `build` target against each file. The task should contain a `Path` element that is a list of projects, solutions, or other files to build.  
    
    The build fails if any MSBuild target fails. If your `whsbuild.yml` file defines a `Version` element and the build is running under a build server, all AssemblyInfo.cs files under each path is updated with appropriate `AssemblyVersion`, `AssemblyFileVersion`, and `AssemblyInformationalVersion` attributes. The `AssemblyInformationalVersion` attribute will contain the full semantic version from `whsbuild.yml` plus some build metadata: the build server's build number, the Git branch, and the Git commit ID.

    .EXAMPLE

    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string[]]
        # an array of taskpaths passed in from the Build function
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        # The path to the `whsbuild.yml` file to use.
        $ConfigurationPath,

        [Parameter(Mandatory=$true)]
        [string]
        # The build configuration to use if you're compiling code, e.g. `Debug`, `Release`.
        $BuildConfiguration,

        [Parameter]
        [switch]

        $RunningUnderBuildServer,
        
        [Parameter]
        [version]

        $Version
    )
  
    Process
    {        
        Set-StrictMode -version 'latest'  

        #setup
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
        $config = Get-Content -Path $ConfigurationPath -Raw | ConvertFrom-Yaml
        [SemVersion.SemanticVersion]$semVersion = $config['Version'] | ConvertTo-WhsCISemanticVersion | Assert-WhsCIVersionAvailable
        
        #build
        foreach( $projectPath in $Path )
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

}