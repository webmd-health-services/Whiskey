function Publish-WhiskeyPowerShellModule
{
    [Whiskey.Task("PublishPowerShellModule")]
    [CmdletBinding()]
    param(

        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $TaskParameter.ContainsKey('RepositoryName') )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "RepositoryName" is mandatory. It should be the name of the PowerShell repository you want to publish to, e.g.

        Build:
        - PublishPowerShellModule:
            Path: mymodule
            RepositoryName: PSGallery
        ')
        return
    }
    $repositoryName = $TaskParameter['RepositoryName']

    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Path" is mandatory. It should a path relative to your whiskey.yml file, to the module directory of the module to publish, e.g.

        Build:
        - PublishPowerShellModule:
            Path: mymodule
            RepositoryName: PSGallery
        ')
        return
    }

    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    if( -not (Test-Path $path -PathType Container) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Path "{0}" isn''t a directory. It must be the path to the root directory of a Powershell module. The directory name must match the name of the module.' -f $path)
        return
    }

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "ApiKeyID" is mandatory. It must be the ID of the API key to use when publishing to the "{0}" repository. Use the `Add-WhiskeyApiKey` function to add API keys to the build.' -f $repositoryName)
        return
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'

    $manifestPath = '{0}\{1}.psd1' -f $path,($path | Split-Path -Leaf)
    if( $TaskParameter.ContainsKey('ModuleManifestPath') )
    {
        $manifestPath = $TaskParameter['ModuleManifestPath']
    }
    if( -not (Test-Path -Path $manifestPath -PathType Leaf) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Module manifest path "{0}" either does not exist or is a directory.' -f $manifestPath)
        return
    }

    $manifest = Get-Content $manifestPath
    $versionString = 'ModuleVersion = ''{0}.{1}.{2}''' -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )
    $manifest = $manifest -replace 'ModuleVersion\s*=\s*(''|")[^''"]*(''|")', $versionString
    $prereleaseString = 'Prerelease = ''{0}''' -f $TaskContext.Version.SemVer2.Prerelease  
    $manifest = $manifest -replace 'Prerelease\s*=\s*(''|")[^''"]*(''|")', $prereleaseString
    $manifest | Set-Content $manifestPath

    Import-WhiskeyPowerShellModule -Name 'PackageManagement','PowerShellGet'

    $commonParams = @{}
    if( $VerbosePreference -in @('Continue','Inquire') )
    {
        $commonParams['Verbose'] = $true
    }
    if( $DebugPreference -in @('Continue','Inquire') )
    {
        $commonParams['Debug'] = $true
    }
    if( (Test-Path -Path 'variable:InformationPreference') )
    {
        $commonParams['InformationAction'] = $InformationPreference
    }

    Get-PackageProvider -Name 'NuGet' -ForceBootstrap @commonParams | Out-Null

    if( -not (Get-PSRepository -Name $repositoryName -ErrorAction Ignore @commonParams) )
    {
        $publishLocation = $TaskParameter['RepositoryUri']
        if( -not $publishLocation )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "RepositoryUri" is mandatory since there is no registered repository named "{0}". The "RepositoryUri" must be the URI to the PowerShall repository to publish to. The repository will be registered for you.' -f $repositoryName)
            return
        }

        $credentialParam = @{ }
        if( $TaskParameter.ContainsKey('CredentialID') )
        {
            $credentialParam['Credential'] = Get-WhiskeyCredential -Context $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'
        }

        Register-PSRepository -Name $repositoryName -SourceLocation $publishLocation -PublishLocation $publishLocation -InstallationPolicy Trusted -PackageManagementProvider NuGet @credentialParam -ErrorAction Stop @commonParams
    }

    Publish-Module -Path $path -Repository $repositoryName -NuGetApiKey $apiKey -ErrorAction Stop @commonParams
}
