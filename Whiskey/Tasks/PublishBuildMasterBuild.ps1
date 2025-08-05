
function Publish-WhiskeyBuildMasterBuild
{
    [CmdletBinding()]
    [Whiskey.Task('PublishBuildMasterBuild', Aliases='PublishBuildMasterPackage')]
    [Whiskey.RequiresPowerShellModule('BuildMasterAutomation',
        Version='4.*',
        VersionParameterName='BuildMasterAutomationVersion')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [String] $ApplicationName,

        [String] $ReleaseName,

        [String] $ApiKeyID,

        [Alias('PackageVariable')]
        [hashtable] $Variable,

        [Alias('PackageName')]
        [String] $BuildNumber,

        [switch] $SkipDeploy,

        [String] $StartAtStage,

        [Alias('Uri')]
        [Uri] $Url
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if (-not $ApplicationName)
    {
        $msg = 'Property "ApplicationName" is mandatory. It must be set to the name of the application in ' +
               'BuildMaster where the build should be published.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $ReleaseName)
    {
        $msg = 'Property "ReleaseName" is mandatory. It must be set to the release name in the BuildMaster ' +
               'application where the build should be published.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $Url)
    {
        $msg = 'Property "Url" is mandatory. It must be set to the BuildMaster URL where the build should be ' +
               'published.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $ApiKeyID = $TaskParameter['ApiKeyID']
    if (-not $ApiKeyID)
    {
        $msg = 'Property "ApiKeyID" is mandatory. It should be the ID of the API key to use when publishing the ' +
               'build to BuildMaster. Use the `Add-WhiskeyApiKey` to add your API key.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $ApiKeyID -PropertyName 'ApiKeyID'
    $bmSession = New-BMSession -Uri $Url -ApiKey $apiKey

    $version = $TaskContext.Version.SemVer2

    $release =
        Get-BMRelease -Session $bmSession -Application $applicationName -Name $ReleaseName -ErrorAction Stop
    if (-not $release)
    {
        $msg = "Unable to create and deploy a release build in BuildMaster. Either the ""${applicationName}"" " +
               "application doesn't exist or it doesn't have a ""${ReleaseName}"" release."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $release | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext

    if (-not $BuildNumber)
    {
        $BuildNumber = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
    }

    if (-not $Variable)
    {
        $Variable = @{}
    }

    $build = New-BMBuild -Session $bmSession `
                         -Release $release `
                         -BuildNumber $BuildNumber `
                         -Variable $Variable `
                         -ErrorAction Stop
    $build | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext

    if ($SkipDeploy)
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('Skipping deploy. SkipDeploy property is true')
    }
    else
    {
        $optionalArgs = @{}
        if ($StartAtStage)
        {
            $optionalArgs['Stage'] = $StartAtStage
        }

        $deployment = Publish-BMReleaseBuild -Session $bmSession -Build $build @optionalArgs -ErrorAction Stop
        $deployment | Format-List | Out-String | Write-WhiskeyVerbose -Context $TaskContext
    }
}
