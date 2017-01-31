
function Invoke-WhsCINuGetPackTask
{
    <#
    .SYNOPSIS
    Creates a NuGet package from .NET .csproj files.

    .DESCRIPTION
    The `Invoke-WhsCINuGetPackTask` runs `nuget.exe` against a list of .csproj files, which create a .nupkg file from that project's build output. The package can be uploaded to NuGet, ProGet, or other package management repository that supports NuGet.

    You must supply the path to the .csproj files to pack with the `Path` parameter, the directory where the packaged .nupkg files go with the `OutputDirectory` parameter, the version being packaged with the `Version` parameter, and the build configuration (e.g. `Debug` or `Release`) via the `BuildConfiguration` parameter.

    To pack multiple projects, you can pipe them to `Invoke-WhsCINuGetPackTask`.

    .EXAMPLE
    Invoke-WhsCINuGetPackageTask -Path $csproj -OutputDirectory '.\output' -Version `1.0.1-rc1` -BuildConfiguration 'Debug'

    Demonstrates how to package the assembly built by `$csproj` into a .nupkg file in the `output` directory. It will generate a package at version `1.0.1-rc1` using the project's `Debug` configuration.

    .EXAMPLE
    $project1,$project2 | Invoke-WhsCINuGetPackTask -OutputDirectory '.\output' -Version `1.0.1-rc1` -BuildConfiguration 'Debug'

    Demonstrates how to package multiple projects by piping them into `Invoke-WhsCINuGetPackTask`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]
        # The path to .csproj files to run the NuGEt pack command against. To pack multiple projects, pipe multiple paths to `Invoke-WhsCINuGetPackTask`.
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        # The directory where the NuGet packages (.nupkg files) will be saved.
        $OutputDirectory,

        [SemVersion.SemanticVersion]
        # The version of the package. Because NuGet doesn't support true semantic versions, any build metadata will be removed. Pre-release metadata must conform to Semantic Version 1.0.
        $Version,

        [Parameter(Mandatory=$true)]
        [string]
        # The build configuration to use, e.g. `Debug` or `Release`.
        $BuildConfiguration
    )

    process
    {
        Set-StrictMode -Version 'Latest'

        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
        if( -not $nugetPath )
        {
            return
        }
        
        $versionArgs = @()
        if( $Version )
        {
            $versionArgs = @( '-Version', $Version )
        }
        $preNupkgCount = Get-ChildItem -Path $OutputDirectory -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
        & $nugetPath pack $versionArgs -OutputDirectory $OutputDirectory -Symbols -Properties ('Configuration={0}' -f $BuildConfiguration) $Path
        $postNupkgCount = Get-ChildItem -Path $OutputDirectory -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
        if( $postNupkgCount -eq $preNupkgCount )
        {
            throw ('NuGet pack command failed. No new .nupkg files found in ''{0}''.' -f $OutputDirectory)
        }
    }
}