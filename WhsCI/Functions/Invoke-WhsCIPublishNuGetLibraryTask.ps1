
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
                    - MyNuspec.csproj')
        }

        $path = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'
        $source = '$TaskContext.ProGetSession.NuGetFeedUri'
        $apiKey = '(''{0}:{1}'' -f $TaskContext.ProGetSession.Credential.UserName,$TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)'
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
        if( -not $nugetPath )
        {
            return
        }
        
        $versionArgs = @()
        if( $TaskContext.Version.NugetVersion )
        {
            $versionArgs = @( '-Version', $TaskContext.Version.NugetVersion )
        }

        New-Item -Path $TaskContext.OutputDirectory -ItemType 'Directory' -ErrorAction Ignore -Force | Out-String | Write-Debug

        $preNupkgCount = Get-ChildItem -Path $TaskContext.OutputDirectory -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
        & $nugetPath pack $versionArgs -OutputDirectory $TaskContext.OutputDirectory -Symbols -Properties ('Configuration={0}' -f $TaskContext.BuildConfiguration) $path |
            Write-CommandOutput
        Invoke-Command -ScriptBlock { & $nugetPath push $path -Source $source -ApiKey $apiKey | Write-CommandOutput }

        $postNupkgCount = Get-ChildItem -Path $TaskContext.OutputDirectory -Filter '*.nupkg' | Measure-Object | Select-Object -ExpandProperty 'Count'
        if( $postNupkgCount -eq $preNupkgCount )
        {
            throw ('NuGet pack command failed. No new .nupkg files found in ''{0}''.' -f $TaskContext.OutputDirectory)
        }
    }
}