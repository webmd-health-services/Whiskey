function Invoke-WhiskeyMSBuild
{
    <#
    .SYNOPSIS
    Invoke-WhiskeyMSBuild builds .NET projects with MSBuild

    .DESCRIPTION
    The MSBuild task is used to build .NET projects with MSBuild from the version of .NET 4 that is installed. Items are built by running the `clean` and `build` target against each file. The TaskParameter should contain a `Path` element that is a list of projects, solutions, or other files to build.  
    
    The build fails if any MSBuild target fails. If your `whiskey.yml` file defines a `Version` element and the build is running under a build server, all AssemblyInfo.cs files under each path is updated with appropriate `AssemblyVersion`, `AssemblyFileVersion`, and `AssemblyInformationalVersion` attributes. The `AssemblyInformationalVersion` attribute will contain the full semantic version from `whiskey.yml` plus some build metadata: the build server's build number, the Git branch, and the Git commit ID.

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhiskeyMSBuild -TaskContext $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to call the `WhiskeyMSBuildTask`. In this case each path in the `Path` element in $TaskParameter relative to your whiskey.yml file, will be built with MSBuild.exe given the build configuration contained in $TaskContext.

    #>
    [Whiskey.Task("MSBuild",SupportsClean=$true)]
    [CmdletBinding()]
    param(
        [object]
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        $TaskContext,
        
        [hashtable]
        # The parameters/configuration to use to run the task. Should be a hashtable that contains the following item(s):
        # 
        # * `Path` (Mandatory): the relative paths to the files/directories to include in the build. Paths should be relative to the whiskey.yml file they were taken from.
        $TaskParameter
    )
  
    function Invoke-WhiskeyMSBuild
    {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [Parameter(Position=0,Mandatory=$true)]
            [Alias('ProjectFile')]
            [string]
            # The project file to run.
            $Path,
    
            [Parameter(Position=1,Mandatory=$false)]
            [Alias('Targets')]
            [string[]]
            # The targets to run.  Seperate multipe targets by commas.
            $Target,
    
            [Parameter(Mandatory=$false)]
            [Alias('Properties')]
            [string[]]
            # The properties to pass.  Seperate multiple name=value pairs with commas.
            $Property = @(),
    
            [Switch]
            # Use 32-bit MSBuild
            $Use32Bit,

            [string[]]
            # Extra arguments to pass to MSBuild.
            $ArgumentList = @()
        )

        #Requires -Version 3
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $pathToMSBuild = "${env:ProgramFiles(x86)}\MSBuild\12.0\bin\amd64\MSBuild.exe"
        if( -not (Test-Path $pathToMSBuild) )
        {
            $pathToMSBuild = "${env:SystemRoot}\Microsoft.Net\Framework64\v4.0.30319\MSBuild.exe"
        }
        if( $Use32Bit -or -not (Test-Path $pathToMSBuild) )
        {
            $pathToMSBuild = "${env:ProgramFiles(x86)}\MSBuild\12.0\bin\MSBuild.exe"
            if( -not (Test-Path $pathToMSBuild) )
            {
                $pathToMSBuild = "${env:SystemRoot}\Microsoft.Net\Framework\v4.0.30319\MSBuild.exe"
            }
        }

        if( -not (Test-path $pathToMSBuild) )
        {
            Write-Error "Unable to find MSBuild.  Has it been installed?"
            return
        }
        Write-Verbose "    Found MSBuild at '$pathToMSBuild'."

        if( $Target )
        {
            $ArgumentList += "/t:{0}" -f ($Target -join ';')
        }

        if( $Property )
        {
            foreach( $item in $Property )
            {
                $name,$value = $item -split '=',2
                $value = $value.Trim('"')
                $value = $value.Trim("'")
                if( $value.EndsWith( '\' ) )
                {
                    $value += '\'
                }
                $ArgumentList += "/p:$name=""{0}""" -f ($value -replace ' ','%20')
            }
        }

        if( $pscmdlet.ShouldProcess($Path, $ArgumentList) )
        {
            & $pathToMSBuild $ArgumentList /nologo $Path
            if( $LASTEXITCODE -ne 0 )
            {
                Write-Error ("MSBuild exited with code {0}." -f $LASTEXITCODE)
            }
        }
    }

    Set-StrictMode -version 'latest'  
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    #setup
    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
    
    # Make sure the Taskpath contains a Path parameter.
    if( -not ($TaskParameter.ContainsKey('Path')) -or -not $TaskParameter['Path'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, relative to your whiskey.yml file, to build with MSBuild.exe, e.g. 
        
        BuildTasks:
        - MSBuild:
            Path:
            - MySolution.sln
            - MyCsproj.csproj')
    }

    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    
    $target = @( 'build' )
    if( $TaskContext.ShouldClean() )
    {
        $target = 'clean'
    }
    else
    {
        if( $TaskParameter.ContainsKey('Target') )
        {
            $target = $TaskParameter['Target']
        }
    }

    foreach( $projectPath in $path )
    {
        Write-Verbose -Message ('  {0}' -f $projectPath)
        $errors = $null
        if( $projectPath -like '*.sln' )
        {
            if( $TaskContext.ShouldClean() )
            {
                $packageDirectoryPath = join-path -path ( Split-Path -Path $projectPath -Parent ) -ChildPath 'packages'
                if( Test-Path -Path $packageDirectoryPath -PathType Container )
                {
                    Write-Verbose -Message ('    Removing NuGet packages at {0}.' -f $packageDirectoryPath)
                    Remove-Item $packageDirectoryPath -Recurse -Force
                }
            }
            else
            {
                Write-Verbose -Message ('    Restoring NuGet packages.')
                & $nugetPath restore $projectPath
            }
        }

        if( $TaskContext.ByBuildServer )
        {
            $projectPath | 
                Split-Path | 
                Get-ChildItem -Filter 'AssemblyInfo.cs' -Recurse | 
                ForEach-Object {
                    $assemblyInfo = $_
                    $assemblyInfoPath = $assemblyInfo.FullName
                    $newContent = Get-Content -Path $assemblyInfoPath | Where-Object { $_ -notmatch '\bAssembly(File|Informational)?Version\b' }
                    $newContent | Set-Content -Path $assemblyInfoPath
                    Write-Verbose -Message ('    Updating version in {0}.' -f $assemblyInfoPath)
    @"
[assembly: System.Reflection.AssemblyVersion("{0}")]
[assembly: System.Reflection.AssemblyFileVersion("{0}")]
[assembly: System.Reflection.AssemblyInformationalVersion("{1}")]
"@ -f $TaskContext.Version.Version,$TaskContext.Version.SemVer2 | Add-Content -Path $assemblyInfoPath
                }
        }

        $verbosity = 'm'
        if( $TaskParameter['Verbosity'] )
        {
            $verbosity = $TaskParameter['Verbosity']
        }

        $configuration = Get-WhiskeyMSBuildConfiguration -Context $TaskContext

        $property = Invoke-Command {
                                        ('Configuration={0}' -f $configuration)

                                        if( $TaskParameter.ContainsKey('Property') )
                                        {
                                            $TaskParameter['Property']
                                        }

                                        if( $TaskParameter.ContainsKey('OutputDirectory') )
                                        {
                                            ('OutDir={0}' -f ($TaskParameter['OutputDirectory'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'OutputDirectory' -Force))
                                        }
                                  }

        $cpuArg = '/maxcpucount'
        if( $TaskParameter['CpuCount'] )
        {
            $cpuArg = '/maxcpucount:{0}' -f $TaskParameter['CpuCount']
        }

        $projectFileName = $projectPath | Split-Path -Leaf
        $logFilePath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('msbuild.{0}.debug.log' -f $projectFileName)
        $msbuildArgs = Invoke-Command {
                                            ('/verbosity:{0}' -f $verbosity)
                                            $cpuArg
                                            $TaskParameter['Argument']
                                            '/filelogger9'
                                            ('/flp9:LogFile={0};Verbosity=d' -f $logFilePath)
                                      } | Where-Object { $_ }
        $separator = '{0}VERBOSE:                   ' -f [Environment]::NewLine
        Write-Verbose -Message ('    Building')
        Write-Verbose -Message ('      Target      {0}' -f ($target -join $separator))
        Write-Verbose -Message ('      Property    {0}' -f ($property -join $separator))
        Write-Verbose -Message ('      Argument    {0}' -f ($msbuildArgs -join $separator))
        Invoke-WhiskeyMSBuild -Path $projectPath `
                            -Target $target `
                            -Property $property `
                            -ArgumentList $msbuildArgs `
                            -ErrorVariable 'errors'
        if( $errors )
        {
            throw ('Building ''{0}'' MSBuild project''s ''{1}'' target(s) in ''{2}'' configuration failed.' -f $projectPath,($target -join ';'),$configuration)
        }
    }
}

