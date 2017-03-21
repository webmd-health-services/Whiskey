
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

    Demonstrates how to package the assembly built by `TaskParameter.Path` into a .nupkg file in the `$Context.OutputDirectory` directory. It will generate a package at version `$Context.NugetVersion` using the project's `$Context.BuildConfiguration` configuration.
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
            $packageVersion = $TaskContext.Version.NuGetVersion
                    
            # Create NuGet package
            & $nugetPath pack -Version $packageVersion -OutputDirectory $TaskContext.OutputDirectory -Symbols -Properties ('Configuration={0}' -f $TaskContext.BuildConfiguration) $path

            # Make sure package was created.
            $filename = '{0}.{1}.nupkg' -f $projectName,$packageVersion
            $packagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
            if( -not (Test-Path -Path $packagePath -PathType Leaf) )
            {
                throw ('Tried to package ''{0}'' but expected NuGet package ''{1}'' does not exist.' -f $path,$packagePath)
            }

            # Make sure symbols package was created
            $filename = '{0}.{1}.symbols.nupkg' -f $projectName,$packageVersion
            $symbolsPackagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
            if( -not (Test-Path -Path $symbolsPackagePath -PathType Leaf) )
            {
                throw ('Tried to package ''{0}'' but expected NuGet symbols package ''{1}'' does not exist.' -f $path,$symbolsPackagePath)
            }

            if( $TaskContext.ByDeveloper )
            {
                continue
            }

            $source = $TaskContext.ProGetSession.NuGetFeedUri
            $apiKey = ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName,$TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
            $packageUri = '{0}/package/{1}/{2}' -f $source,$projectName,$packageVersion
            
            # Make sure this version doesn't exist.
            $packageExists = $false
            try
            {
                Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
                $packageExists = $true
            }
            catch [Net.WebException]
            {
                if( ([Net.HttpWebResponse]([Net.WebException]$_.Exception).Response).StatusCode -ne [Net.HttpStatusCode]::NotFound )
                {
                    throw ([Net.HttpWebResponse]([Net.WebException]$_.Exception))
                }
                $Global:error.Clear()
            }

            if( $packageExists )
            {
                throw ('{0} {1} already exists. Please increment your library''s version number in ''{2}''.' -f $projectName,$packageVersion,$TaskContext.ConfigurationPath)
            }

            # Publish package and symbols to NuGet
            Invoke-Command -ScriptBlock { & $nugetPath push $packagePath -Source $source -ApiKey $apiKey}
            Invoke-Command -ScriptBlock { & $nugetPath push $symbolsPackagePath -Source $source -ApiKey $apiKey}

            # Since NuGet sux0r, we have to check that the package exists in the repo to test that the nuget push command succeeded or not
            $packageExists = $false
            try
            {
                Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
                $packageExists = $true
            }
            catch [Net.WebException]
            {
            }

            if( -not $packageExists )
            {
                throw ('NuGet push command failed to publish NuGet package to ''{0}''. Please see build output for more information.' -f $packageUri)
            }
        }

    }
} 

