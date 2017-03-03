
function New-WhsCIBuildMasterPackage
{
    <#
    .SYNOPSIS
    Starts an application's BuildMaster pipeline.

    .DESCRIPTION
    The `New-WhsCIBuildMasterPackage` function starts an application's BuildMaster pipeline. The object passed to the `TaskContext` parameter must have the following properties:

    * `BuildMasterSession`: a session object representing the instance of BuildMaster to connect to.
    * `ApplicationName`: the name of the application whose pipeline to start. The application *must* exist in BuildMaster.
    * `ReleaseName`: the name of the release in BuildMaster whose pipeline to start. If you're using Gitflow, this should be one of `develop`, `release`, or `master`, depending on the branch being built.
    * `Version`: the semantic version of the package that should be deployed. This is passed to BuildMaster as the `ProGetPackageVersion` package variable.

    It may also have the following optional parameters:

    * `PackageVariables`: A hashtable of variables to set in the BuildMaster package that will be created by this function.

    .EXAMPLE
    New-WhsCIBuildMasterPackage -TaskContext $context

    Demonstrates how to call `New-WhsCIBuildMasterPackage`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context of the build currently being run.
        $TaskContext
    )

    Set-StrictMode -Version 'Latest'
    
    if( $TaskContext.ByDeveloper )    
    {
        return
    }

    $buildMasterSession = $TaskContext.BuildMasterSession
    $name = $TaskContext.ApplicationName
    $releaseName = $TaskContext.ReleaseName
    $version = $TaskContext.Version

    $variables = $TaskContext.PackageVariables

    if( -not $variables.ContainsKey('ProGetPackageVersion') -or -not $variables.ContainsKey('ProGetPackageName') )
    {
        Write-Warning -Message ('Unable to create a new release package and start a deploy in BuildMaster. It looks like your application didn''t package anything. To deploy your application with BuildMaster, add a package task to {1} and re-run your build. Run `help about_WhsCI_Tasks` to see a list of tasks.`')
        return
    }

    $release = Get-BMRelease -Session $buildMasterSession -Application $name -Name $releaseName
    $release | Format-List | Out-String | Write-Verbose

    $packageName = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
    $package = New-BMReleasePackage -Session $buildMasterSession -Release $release -PackageNumber $packageName -Variable $variables
    $package | Format-List | Out-String | Write-Verbose

    $deployment = Publish-BMReleasePackage -Session $buildMasterSession -Package $package
    $deployment | Format-List | Out-String | Write-Verbose

}