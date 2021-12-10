
function Publish-WhiskeyPowerShellScript
{
    [Whiskey.Task('PublishPowerShellScript')]
    [Whiskey.RequiresPowerShellModule('PackageManagement', Version='1.4.7', VersionParameterName='PackageManagementVersion')]
    [Whiskey.RequiresPowerShellModule('PowerShellGet', Version='2.2.5', VersionParameterName='PowerShellGetVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
        [String] $Path,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String] $ScriptManifestPath,

        [String] $RepositoryName,

        [Alias('RepositoryUri')]
        [String] $RepositoryLocation,

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
        [String] $CredentialID
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $scriptManifestPath = '{0}\{1}.ps1' -f $Path,($Path | Split-Path -Leaf)
    if( $ScriptManifestPath )
    {
        $scriptManifestPath = $ScriptManifestPath
    }

    if( -not (Test-Path -Path $scriptManifestPath -PathType Leaf) )
    {
        $msg = "Script manifest path ""$($scriptManifestPath)"" either does not exist or is a directory."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $scriptManifestPath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $msg = "Script manifest $($scriptManifestPath.Path) is not valid. The value of the path must resolve to a single
                file that has a '.ps1' extension. Change the value of the path to a valid ps1 file and then try again."

        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }

    $scriptManifest = Test-ScriptFileInfo -Path $scriptManifestPath

    $manifestContent = Get-Content $scriptManifest.Path
    $versionString = '.VERSION {0}.{1}.{2}' -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )
    $manifestContent = $manifestContent -replace '.VERSION\s[^''"]*', $versionString

    if( $TaskContext.Version.SemVer2.Prerelease )
    {
        $prereleaseString = "$($versionString)-{0}" -f $TaskContext.Version.SemVer2.Prerelease  
        $manifestContent = $manifestContent -replace '.VERSION\s[^''"]*', $prereleaseString
    }

    $manifestContent | Set-Content $scriptManifest.Path

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

    Write-WhiskeyDebug -Context $TaskContext -Message 'Bootstrapping NuGet packageprovider.'
    Get-PackageProvider -Name 'NuGet' -ForceBootstrap @commonParams | Out-Null

    $createTempRepo = $false
    $infoMsg = ''
    if( -not $RepositoryLocation -and -not $RepositoryName )
    {
        $createTempRepo = $true
        $RepositoryLocation = $TaskContext.OutputDirectory.FullName
        $infoMsg = """$($RepositoryLocation | Resolve-WhiskeyRelativePath)"""
    }
    elseif( $RepositoryLocation )
    {
        $publishTo =
            Get-PSRepository -ErrorAction Ignore @commonParams | Where-Object 'PublishLocation' -eq $RepositoryLocation
        if( $publishTo )
        {
            $RepositoryName = $publishTo.Name
        }
        else
        {
            $createTempRepo = $true
        }
    }
    elseif( $RepositoryName )
    {
        $publishTo = Get-PSRepository -ErrorAction Ignore @commonParams | Where-Object 'Name' -eq $RepositoryName
        if( -not $publishTo )
        {
            Get-PSRepository | Format-Table -AutoSize
            $msg = "Unable to publish PowerShell script ""$($scriptManifest.ScriptBase | Resolve-WhiskeyRelativePath)"" to " +
                   "repository ""$($RepositoryName)"": a repository with that name doesn't exist. Update your " +
                   'PublishPowerShellScript task with the name of one of the repository''s that ' +
                   'exists (see above), use the "RepositoryLocation" to specify the URI or path to a repository, ' +
                   'or leave "RepositoryName" blank to publish to the build output directory.'
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }
        $RepositoryLocation = $publishTo.PublishLocation
    }

    try
    {
        if( $createTempRepo )
        {
            $credentialParam = @{ }
            if( $CredentialID )
            {
                $credentialParam['Credential'] =
                    Get-WhiskeyCredential -Context $TaskContext -ID $CredentialID -PropertyName 'CredentialID'
            }

            $tempNameSuffix = [IO.Path]::GetRandomFileName() -replace '\.', ''
            $RepositoryName = "Whiskey-$($TaskContext.BuildRoot.FullName)-$($tempNameSuffix)"

            $msg = "Registering PowerShell repository ""$($RepositoryName)"" at ""$($RepositoryLocation)""."
            Write-WhiskeyVerbose -Context $TaskContext -Message $msg
            # Do *not* ErrorAction Stop this. It causes a handled error deep in the bowels of PackageManagement to
            # cause Register-PSRepository to fail.
            Register-PSRepository -Name $RepositoryName `
                                  -SourceLocation $RepositoryLocation `
                                  -PublishLocation $RepositoryLocation `
                                  -InstallationPolicy Trusted `
                                  -PackageManagementProvider NuGet `
                                  -ErrorAction Continue `
                                  @credentialParam `
                                  @commonParams

            if( -not (Get-PSRepository -Name $RepositoryName) )
            {
                Get-PSRepository | Format-Table -Auto
                $msg = "Register-PSRepository didn't register ""$($RepositoryName)"" at location " +
                       """$($RepositoryLocation)""."
                Stop-WhiskeyTask -TaskContext $Context -Message $msg
                return
            }
        }

        $apiKeyParam = @{}
        $apiKeyID = $TaskParameter['ApiKeyID']
        if( $apiKeyID )
        {
            $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'
            if( $apiKey )
            {
                $apiKeyParam['NuGetApiKey'] = $apiKey
            }
        }

        if( -not $infoMsg )
        {
            $infoMsg = "repository ""$($RepositoryName)"" at ""$($RepositoryLocation)"""
        }
        $msg = "Publishing PowerShell script ""$($Path | Resolve-WhiskeyRelativePath)"" to $($infoMsg)."
        Write-WhiskeyInfo -Context $TaskContext -Message $msg
        # Use the Force switch to allow publishing versions that come *before* the latest version.
        Publish-Script -Path $scriptManifestPath -Repository $RepositoryName -Force @apiKeyParam @commonParams -ErrorAction Stop
    }
    finally
    {
        if( $createTempRepo )
        {
            $msg = "Unregistering temporary PowerShell repository ""$($RepositoryName)""."
            Write-WhiskeyVerbose -Context $TaskContext -Message $msg
            Unregister-PSRepository -Name $RepositoryName
        }
    }
}