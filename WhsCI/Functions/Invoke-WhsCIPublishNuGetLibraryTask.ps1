
function Invoke-WhsCIPublishNuGetLibraryTask
{
    <#
    .SYNOPSIS
    Creates a NuGet package from .NET .csproj files.

    .DESCRIPTION
    The `Invoke-WhsCINuGetPackTask` runs `nuget.exe` against a list of .csproj files, which create a .nupkg file from that project's build output. The package can be uploaded to NuGet, ProGet, or other package management repository that supports NuGet.

    You must supply the path to the .csproj files to pack with the `$TaskParameter.Path` parameter, the directory where the packaged .nupkg files go with the `$Context.OutputDirectory` parameter, the version being packaged with the `$Context.Version` parameter, and the build configuration (e.g. `Debug` or `Release`) via the `$Context.BuildConfiguration` parameter.

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhsCINuGetPackageTask -Context $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to package the assembly built by `TaskParameter.Path` into a .nupkg file in the `$Context.OutputDirectory` directory. It will generate a package at version `$Context.ReleaseVersion` using the project's `$Context.BuildConfiguration` configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    process
    {
        Set-StrictMode -Version 'Latest'

        if( -not ($TaskParameter.ContainsKey('Path')))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of assemblies whose tests to run, e.g. 
        
            BuildTasks:
                - NuGetPack:
                    Path:
                    - MyProject.csproj
                    - MyNuspec.nuspec')
        }

        $paths = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'
       
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
        if( -not $nugetPath )
        {
            return
        }
        foreach ($path in $paths)
        {
            $projectName = [IO.Path]::GetFileNameWithoutExtension(($path | Split-Path -Leaf))
            $packageVersion = $TaskContext.Version.ReleaseVersion
                    
            # Create NuGet package
            & $nugetPath pack -Version $packageVersion -OutputDirectory $TaskContext.OutputDirectory -Symbols -Properties ('Configuration={0}' -f $TaskContext.BuildConfiguration) $path

            # Make sure package was created.
            $filename = '{0}.{1}.nupkg' -f $projectName,$packageVersion
            $packagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
            if( -not (Test-Path -Path $packagePath -PathType Leaf) )
            {
                Stop-WhsCITask -TaskContext $TaskContext -Message ('We ran nuget pack against ''{0}'' but the expected NuGet package ''{1}'' does not exist.' -f $path,$packagePath)
            }

            # Make sure symbols package was created
            $filename = '{0}.{1}.symbols.nupkg' -f $projectName,$packageVersion
            $symbolsPackagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
            if( -not (Test-Path -Path $symbolsPackagePath -PathType Leaf) )
            {
                Stop-WhsCITask -TaskContext $TaskContext -Message ('We ran nuget pack against ''{0}'' to create a symbols package but the expected NuGet symbols package ''{1}'' does not exist.' -f $path,$symbolsPackagePath)
            }

            if( $TaskContext.ByDeveloper )
            {
                continue
            }

            $source = $TaskContext.ProGetSession.NuGetFeed
            $apiKey = ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName,$TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
            $packageUri = '{0}/package/{1}/{2}' -f $source,$projectName,$packageVersion
            
            # Make sure this version doesn't exist.
            $packageExists = $false
            $numErrorsAtStart = $Global:Error.Count
            try
            {
                Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
                $packageExists = $true
            }
            catch [Net.WebException]
            {
                if( ([Net.HttpWebResponse]([Net.WebException]$_.Exception).Response).StatusCode -ne [Net.HttpStatusCode]::NotFound )
                {
                    Stop-WhsCITask -TaskContext $TaskContext -Message ('Failure checking if {0} {1} package already exists at {2}. The web request returned a {3} status code.' -f $projectName,$packageVersion,$packageUri,$_.Exception.Response.StatusCode)
                }

                for( $idx = 0; $idx -lt ($Global:Error.Count - $numErrorsAtStart); ++$idx )
                {
                    $Global:Error.RemoveAt(0)
                }
            }

            if( $packageExists )
            {
                Stop-WhsCITask -TaskContext $TaskContext -Message ('{0} {1} already exists. Please increment your library''s version number in ''{2}''.' -f $projectName,$packageVersion,$TaskContext.ConfigurationPath)
            }

            # Publish package and symbols to NuGet
            Invoke-Command -ScriptBlock { & $nugetPath push $packagePath -Source $source -ApiKey $apiKey}
            Invoke-Command -ScriptBlock { & $nugetPath push $symbolsPackagePath -Source $source -ApiKey $apiKey}
            try
            {
                Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
            }
            catch [Net.WebException]
            {
                Stop-WhsCITask -TaskContext $TaskContext -Message ('Failed to publish NuGet package {0} {1} to {2}. When we checked if that package existed, we got a {3} HTTP status code. Please see build output for more information.' -f $projectName,$packageVersion,$packageUri,$_.Exception.Response.StatusCode)
            }
        }

    }
} 

