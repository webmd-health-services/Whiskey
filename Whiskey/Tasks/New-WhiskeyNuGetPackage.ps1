
function New-WhiskeyNuGetPackage
{
    <#
    .SYNOPSIS
    Creates a NuGet package from .NET .csproj files.

    .DESCRIPTION
    The `Invoke-WhiskeyNuGetPackTask` runs `nuget.exe` against a list of .csproj files, which create a .nupkg file from that project's build output. The package can be uploaded to NuGet, ProGet, or other package management repository that supports NuGet.

    You must supply the path to the .csproj files to pack with the `$TaskParameter.Path` parameter, the directory where the packaged .nupkg files go with the `$Context.OutputDirectory` parameter, the version being packaged with the `$Context.Version` parameter, and the build configuration (e.g. `Debug` or `Release`) via the `$Context.BuildConfiguration` parameter.

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhiskeyNuGetPackageTask -Context $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to package the assembly built by `TaskParameter.Path` into a .nupkg file in the `$Context.OutputDirectory` directory. It will generate a package at version `$Context.ReleaseVersion` using the project's `$Context.BuildConfiguration` configuration.
    #>
    [Whiskey.Task("NuGetPack")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if( $Clean )
    {
        return
    }

    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Path'' is mandatory. It should be one or more paths to .csproj or .nuspec files to pack, e.g. 
            
    BuildTasks:
    - PublishNuGetPackage:
        Path:
        - MyProject.csproj
        - MyNuspec.nuspec
    ')
    }

    $paths = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
       
    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
    if( -not $nugetPath )
    {
        return
    }

    foreach ($path in $paths)
    {
        $projectName = [IO.Path]::GetFileNameWithoutExtension(($path | Split-Path -Leaf))
        $packageVersion = $TaskContext.Version.SemVer1
                    
        # Create NuGet package
        $configuration = 'Debug'
        if( $TaskContext.ByBuildServer )
        {
            $configuration = 'Release'
        }
        & $nugetPath pack -Version $packageVersion -OutputDirectory $TaskContext.OutputDirectory -Symbols -Properties ('Configuration={0}' -f $configuration) $path

        # Make sure package was created.
        $filename = '{0}.{1}.nupkg' -f $projectName,$packageVersion
        $packagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
        if( -not (Test-Path -Path $packagePath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('We ran nuget pack against ''{0}'' but the expected NuGet package ''{1}'' does not exist.' -f $path,$packagePath)
        }

        # Make sure symbols package was created
        $filename = '{0}.{1}.symbols.nupkg' -f $projectName,$packageVersion
        $symbolsPackagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
        if( -not (Test-Path -Path $symbolsPackagePath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('We ran nuget pack against ''{0}'' to create a symbols package but the expected NuGet symbols package ''{1}'' does not exist.' -f $path,$symbolsPackagePath)
        }
    }
}
