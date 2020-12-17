
function Publish-WhiskeyPowerShellModule
{
    [Whiskey.Task('PublishPowerShellModule')]
    # If you want to upgrade the PackageManagement and PowerShellGet versions, you must also update:
    # * Test\Find-WhiskeyPowerShellModule.Tests.ps1
    # * Whiskey\Functions\Find-WhiskeyPowerShellModule.ps1
    # * whiskey.yml
    [Whiskey.RequiresPowerShellModule('PackageManagement',Version='1.4.5',VersionParameterName='PackageManagementVersion')]
    [Whiskey.RequiresPowerShellModule('PowerShellGet',Version='2.2.1',VersionParameterName='PowerShellGetVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
        [String]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $TaskParameter.ContainsKey('RepositoryName') )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext `
                         -Message ('Property "RepositoryName" is mandatory. It should be the name of the PowerShell repository you want to publish to, e.g.

        Build:
        - PublishPowerShellModule:
            Path: mymodule
            RepositoryName: PSGallery
        ')
        return
    }
    $repositoryName = $TaskParameter['RepositoryName']

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext `
                         -Message ('Property "ApiKeyID" is mandatory. It must be the ID of the API key to use when publishing to the "{0}" repository. Use the `Add-WhiskeyApiKey` function to add API keys to the build.' -f $repositoryName)
        return
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'

    $manifestPath = '{0}\{1}.psd1' -f $Path,($Path | Split-Path -Leaf)
    if( $TaskParameter.ContainsKey('ModuleManifestPath') )
    {
        $manifestPath = $TaskParameter['ModuleManifestPath']
    }
    if( -not (Test-Path -Path $manifestPath -PathType Leaf) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext `
                         -Message ('Module manifest path "{0}" either does not exist or is a directory.' -f $manifestPath)
        return
    }

    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Ignore
    if( $TaskContext.Version.SemVer2.Prerelease -and `
        (-not ($manifest.PrivateData) -or `
        -not ($manifest.PrivateData | Get-Member 'Keys') -or `
        -not $manifest.PrivateData.ContainsKey('PSData') -or `
        -not ($manifest.PrivateData['PSData'] | Get-Member 'Keys') -or `
        -not $manifest.PrivateData['PSData'].ContainsKey('Prerelease')) )
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ("Module manifest ""$($manifestPath)"" is missing a ""Prerelease"" property. Please make sure the manifest's PrivateData hashtable contains a PSData key with a Prerelease property, e.g.
        
    @{
        PrivateData = @{
            PSData = @{
                Prerelease = '';
            }
        }
    }
        ")
        return
    }

    $manifest = Get-Content $manifestPath
    $versionString = 'ModuleVersion = ''{0}.{1}.{2}''' -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )
    $manifest = $manifest -replace 'ModuleVersion\s*=\s*(''|")[^''"]*(''|")', $versionString
    $prereleaseString = 'Prerelease = ''{0}''' -f $TaskContext.Version.SemVer2.Prerelease  
    $manifest = $manifest -replace 'Prerelease\s*=\s*(''|")[^''"]*(''|")', $prereleaseString
    $manifest | Set-Content $manifestPath

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
    $registeredRepositories = Get-PSRepository -ErrorAction Ignore @commonParams

    if( $repositoryName -notin $registeredRepositories.Name )
    {
        $publishLocation = $TaskParameter['RepositoryUri']
        if( -not $publishLocation )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext `
                             -Message ('Property "RepositoryUri" is mandatory since there is no registered repository named "{0}". The "RepositoryUri" must be the URI to the PowerShall repository to publish to. The repository will be registered for you.' -f $repositoryName)
            return
        }

        $credentialParam = @{ }
        if( $TaskParameter.ContainsKey('CredentialID') )
        {
            $credentialParam['Credential'] = 
                Get-WhiskeyCredential -Context $TaskContext `
                                      -ID $TaskParameter['CredentialID'] `
                                      -PropertyName 'CredentialID'
        }

        $exists = $registeredRepositories | Where-Object { $_.SourceLocation -eq $publishLocation }
        if( $exists )
        {
            $repositoryName = $exists.Name 
            Write-WhiskeyWarning -Context $TaskContext `
                                 -Message ('The URI "{0}" is registered as the {1} repository. Please update your whiskey.yml file to use this repository name.' -f $publishLocation, $repositoryName)
        }
        else
        {
            Register-PSRepository -Name $repositoryName `
                                  -SourceLocation $publishLocation `
                                  -PublishLocation $publishLocation `
                                  -InstallationPolicy Trusted `
                                  -PackageManagementProvider NuGet @credentialParam `
                                  -ErrorAction Stop @commonParams
        }
    }

    # Use the Force switch to allow publishing versions that come *before* the latest version.
    Publish-Module -Path $Path `
                   -Repository $repositoryName `
                   -NuGetApiKey $apiKey `
                   -Force `
                   -ErrorAction Stop `
                   @commonParams
}
