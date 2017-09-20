
function Publish-WhiskeyBuildMasterPackage
{
    <#
    .SYNOPSIS
    Creates and deploys a release package in BuildMaster.

    .DESCRIPTION
    The `PublishBuildMasterPackage` task creates a release package in BuildMaster. By default, it also starts a deployment of the package to the first stage of the release's pipeline. It uses the `New-BMPackage` function from the `BuildMasterAutomation` module to create the package. It uses the `Publish-BMReleasePackage` to start the deployment.

    Set the `ApplicationName` property to the name of the application in BuildMaster where the package should be published. Set the `Uri` property to the base URI to BuildMaster. Set the `ApiKeyID` property to the ID of the API key to use when publishing the package to BuildMaster. Use the `Add-WhiskeyApiKey` to add your API key.

    Set the `DeployTo` property to map an SCM branch to its corresponding BuildMaster release where packages should be created and deployed. `BranchName` and `ReleaseName` are required. The task will fail if the current branch is not mapped to an existing release. `StartAtStage` and `SkipDeploy` are optional. By default, a deployment will start at the first stage of a release pipeline and will not be skipped.

    ## Property

    * `ApplicationName` (mandatory): the name of the application in BuildMaster where the package should be published.
    * `Uri` (mandatory): the BuildMaster URI where the package should be published..
    * `ApiKeyID` (mandatory): the ID of the API key to use when publishing the package to BuildMaster. Use the `Add-WhiskeyApiKey` to add your API key.
    * `DeployTo` (mandatory): map an SCM branch to its corresponding BuildMaster release where packages should be created and deployed.
    * `PackageVariable`: the variables to configure in BuildMaster unique to this package. By default, the package will not have any package-level variables.
    * `PackageName`: the name of the package that will be created in BuildMaster. By default, the package will be named "MajorVersion.MinorVersion.PatchVersion"

    ## Examples

    ### Example 1

        PublishTasks:
        - PublishBuildMasterPackage:
            ApplicationName: TestApplication
            Uri: https://buildmaster.example.com
            ApiKeyID: buildmaster.example.com
            DeployTo:
            - BranchName: master
              ReleaseName: ProdRelease

    Demonstrates the minimal configuration needed to create and deploy a package. In this case (when building on the `master` branch), a package will be created on the `ProdRelease` release of the `TestApplication` application at `https://buildmaster.example.com` using the API key with the `buildmaster.example.com` ID. The package will be deployed to the first stage of `ProdRelease` release's pipeline.

    ### Example 2

        PublishTasks:
        - PublishBuildMasterPackage:
            ApplicationName: TestApplication
            Uri: https://buildmaster.example.com
            PackageName: TestPackage
            ApiKeyID: buildmaster.example.com
            DeployTo:
            - BranchName: master
              ReleaseName: ProdRelease

    In this case, a package will be created on the `ProdRelease` release of the `TestApplication` application and will be named `TestPackage` instead of the default "MajorVersion.MinorVersion.PatchVersion". The package will be deployed to the first stage of `ProdRelease` release's pipeline.

    ### Example 3

        PublishTasks:
        - PublishBuildMasterPackage:
            ApplicationName: TestApplication
            Uri: https://buildmaster.example.com
            ApiKeyID: buildmaster.example.com
            DeployTo:
            - BranchName:
              - develop
              - feature*
              ReleaseName: TestRelease
              StartAtStage: Test
            - BranchName: prod
              ReleaseName: ProdRelease
              SkipDeploy: true

    When building on `develop`, `feature/NewFunction`, or `feature68` branches, a package will be created on the `TestRelease` release of the `TestApplication` application. The package will be deployed to the `Test` stage of the `TestRelease` release's pipeline.

    When building on `prod` branch, a package will be created on the `ProdRelease` release of the `TestApplication` application. The package will be created, but will not be deployed.

    When building on `unmapped` branch, the task will fail with an error stating that the current branch must be mapped to a `ReleaseName`. No package will be created or deployed.
    #>
    [CmdletBinding()]
    [Whiskey.Task("PublishBuildMasterPackage")]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $applicationName = $TaskParameter['ApplicationName']
    if( -not $applicationName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApplicationName'' is mandatory. It must be set to the name of the application in BuildMaster where the package should be published.')
    }
    
    $branch = $TaskContext.BuildMetadata.ScmBranch
    $releaseName = $null
    $startAtStage = $null
    $skipDeploy = $null
    
    if( $TaskParameter['DeployTo'] )
    {
        $idx = 0
        Write-Verbose -Message ('DeployTo')
        :deploy foreach( $item in $TaskParameter['DeployTo'] )
        {
            foreach( $wildcard in $item['BranchName'] )
            {
                if( $branch -like $wildcard )
                {
                    Write-Verbose -Message ('               {0}     -like  {1}' -f $branch,$wildcard)
                    $releaseName = $item['ReleaseName']
                    $startAtStage = $item['StartAtStage']
                    $skipDeploy = $item['SkipDeploy']
                    break deploy
                }
                else
                {
                    Write-Verbose -Message ('               {0}  -notlike  {1}' -f $branch,$wildcard)
                }
            }
            $idx++
        }
    }
    
    if( -not $releaseName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ReleaseName'' is mandatory. It must be set to the release name in the BuildMaster application where the package should be published. Use the ''DeployTo'' property to map the current branch to a ''ReleaseName''.')
    }
    
    $buildmasterUri = $TaskParameter['Uri']
    if( -not $buildmasterUri )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Uri'' is mandatory. It must be set to the BuildMaster URI where the package should be published.')
    }

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApiKeyID'' is mandatory. It should be the ID of the API key to use when publishing the package to BuildMaster. Use the `Add-WhiskeyApiKey` to add your API key.')
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $TaskParameter['ApiKeyID'] -PropertyName 'ApiKeyID'
    $buildMasterSession = New-BMSession -Uri $TaskParameter['Uri'] -ApiKey $apiKey

    $version = $TaskContext.Version.SemVer2

    $variables = $TaskParameter['PackageVariable']

    $release = Get-BMRelease -Session $buildMasterSession -Application $applicationName -Name $releaseName -ErrorAction Stop
    if( -not $release )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to create and deploy a release package in BuildMaster. Either the ''{0}'' application doesn''t exist or it doesn''t have a ''{1}'' release.' -f $applicationName,$releaseName)
    }

    $release | Format-List | Out-String | Write-Verbose

    if( $TaskParameter['PackageName'] )
    {
        $packageName = $TaskParameter['PackageName']
    }
    else
    {
        $packageName = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
    }
    
    $package = New-BMPackage -Session $buildMasterSession -Release $release -PackageNumber $packageName -Variable $variables -ErrorAction Stop
    $package | Format-List | Out-String | Write-Verbose

    if( $skipDeploy )
    {
        Write-Verbose -Message ('''SkipDeploy'' property is configured for the ''{0}'' branch. The BuildMaster release package is ready for manual deployment.' -f $branch)
    }
    else
    {
        $optionalParams = @{ }
        if( $startAtStage )
        {
            $optionalParams['Stage'] = $startAtStage
        }
        
        $deployment = Publish-BMReleasePackage -Session $buildMasterSession -Package $package @optionalParams -ErrorAction Stop
        $deployment | Format-List | Out-String | Write-Verbose
    }
}
