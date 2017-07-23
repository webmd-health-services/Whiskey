
function New-WhiskeyNuGetPackage
{
    [Whiskey.Task("NuGetPack")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

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
        $configuration = Get-WhiskeyMSBuildConfiguration -Context $TaskContext

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
