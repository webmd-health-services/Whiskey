
function New-WhiskeyBuildMasterPackage
{
    <#
    .SYNOPSIS
    Starts an application's BuildMaster pipeline.

    .DESCRIPTION
    The `New-WhiskeyBuildMasterPackage` function starts an application's BuildMaster pipeline. The object passed to the `TaskContext` parameter must have the following properties:

    * `BuildMasterSession`: a session object representing the instance of BuildMaster to connect to.
    * `ApplicationName`: the name of the application whose pipeline to start. The application *must* exist in BuildMaster.
    * `ReleaseName`: the name of the release in BuildMaster whose pipeline to start. If you're using Gitflow, this should be one of `develop`, `release`, or `master`, depending on the branch being built.
    * `Version`: the semantic version of the package that should be deployed. This is passed to BuildMaster as the `ProGetPackageVersion` package variable.

    It may also have the following optional parameters:

    * `PackageVariables`: A hashtable of variables to set in the BuildMaster package that will be created by this function.

    .EXAMPLE
    New-WhiskeyBuildMasterPackage -TaskContext $context

    Demonstrates how to call `New-WhiskeyBuildMasterPackage`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context of the build currently being run.
        $TaskContext
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $deployPackage = $true
    if( $TaskContext.Configuration.ContainsKey('DeployPackage') )
    {
        $deployPackage = $TaskContext.Configuration['DeployPackage']
    }
    
    if( $TaskContext.ByDeveloper -or -not $deployPackage )
    {
        return
    }

    $buildMasterSession = $TaskContext.BuildMasterSession
    $name = $TaskContext.ApplicationName
    $releaseName = $TaskContext.ReleaseName
    $version = $TaskContext.Version.SemVer2

    $variables = $TaskContext.PackageVariables

    if( -not $variables.ContainsKey('ProGetPackageVersion') -or -not $variables.ContainsKey('ProGetPackageName') )
    {
        return
    }

    $release = Get-BMRelease -Session $buildMasterSession -Application $name -Name $releaseName
    if( -not $release )
    {
        throw (@'
Unable to create and deploy a release package in BuildMaster. Either the '{0}' application doesn't exist or it doesn't have a '{1}' release.
 
If you don't want to publish to BuildMaster, set the `PublishToBuildMaster` property in '{2}' to `false`, e.g.
 
    PublishToBuildMaster: false
     
If your application name in BuildMaster is not '{0}', set the `ApplicationName` property in '{2}' to the name of your application, e.g.
 
    ApplicationName: APPLICATION_NAME
     
If your release name in BuildMaster is not '{1}', set the `ReleaseName` property in '{2}' file to the name of your release, e.g.
 
    ReleaseName: RELEASE_NAME
     
If you don't want to publish to BuildMaster on this branch, create a `PublishOn` property and list the branches you want to publish on, e.g.
 
    PublishOn:
    - master
 
'@ -f $name,$releaseName,$TaskContext.ConfigurationPath)
    }

    $release | Format-List | Out-String | Write-Verbose

    $packageName = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
    $package = New-BMReleasePackage -Session $buildMasterSession -Release $release -PackageNumber $packageName -Variable $variables
    $package | Format-List | Out-String | Write-Verbose

    $deployment = Publish-BMReleasePackage -Session $buildMasterSession -Package $package
    $deployment | Format-List | Out-String | Write-Verbose

}
