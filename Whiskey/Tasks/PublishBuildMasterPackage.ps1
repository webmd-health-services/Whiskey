
function Publish-WhiskeyBuildMasterPackage
{
    [CmdletBinding()]
    [Whiskey.Task('PublishBuildMasterPackage')]
    [Whiskey.RequiresPowerShellModule('BuildMasterAutomation',
        Version='0.6.*',
        VersionParameterName='BuildMasterAutomationVersion')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Alias('Uri')]
        [Uri] $Url
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $applicationName = $TaskParameter['ApplicationName']
    if( -not $applicationName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApplicationName'' is mandatory. It must be set to the name of the application in BuildMaster where the package should be published.')
        return
    }

    $releaseName = $TaskParameter['ReleaseName']
    if( -not $releaseName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ReleaseName'' is mandatory. It must be set to the release name in the BuildMaster application where the package should be published.')
        return
    }

    if (-not $Url)
    {
        $msg = "Property ""Url"" is mandatory. It must be set to the BuildMaster URL where the package should be " +
               'published.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApiKeyID'' is mandatory. It should be the ID of the API key to use when publishing the package to BuildMaster. Use the `Add-WhiskeyApiKey` to add your API key.')
        return
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $TaskParameter['ApiKeyID'] -PropertyName 'ApiKeyID'
    $buildMasterSession = New-BMSession -Uri $Url -ApiKey $apiKey

    $version = $TaskContext.Version.SemVer2

    $variables = $TaskParameter['PackageVariable']

    $release = Get-BMRelease -Session $buildMasterSession -Application $applicationName -Name $releaseName -ErrorAction Stop
    if( -not $release )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to create and deploy a release package in BuildMaster. Either the ''{0}'' application doesn''t exist or it doesn''t have a ''{1}'' release.' -f $applicationName,$releaseName)
        return
    }

    $release | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext

    if( $TaskParameter['PackageName'] )
    {
        $packageName = $TaskParameter['PackageName']
    }
    else
    {
        $packageName = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
    }

    $package = New-BMPackage -Session $buildMasterSession -Release $release -PackageNumber $packageName -Variable $variables -ErrorAction Stop
    $package | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext

    if( ConvertFrom-WhiskeyYamlScalar -InputObject $TaskParameter['SkipDeploy'] )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('Skipping deploy. SkipDeploy property is true')
    }
    else
    {
        $optionalParams = @{ 'Stage' = $TaskParameter['StartAtStage'] }

        $deployment = Publish-BMReleasePackage -Session $buildMasterSession -Package $package @optionalParams -ErrorAction Stop
        $deployment | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext
    }
}
