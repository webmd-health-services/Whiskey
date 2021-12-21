
function Publish-WhiskeyPSObject
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $Context,
        
        [Parameter(Mandatory, ParameterSetName='Module')]
        [Management.Automation.PSModuleInfo] $ModuleInfo,
        
        [Parameter(Mandatory, ParameterSetName='Script')]
        [PSCustomObject] $ScriptInfo,
        
        [String] $RepositoryName,
        
        [String] $RepositoryLocation,
        
        [String] $CredentialID,
        
        [String] $ApiKeyID
    )

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
            if( $ScriptInfo )
            {
                $msg = "Unable to publish PowerShell script ""$($ScriptInfo.ScriptBase | Resolve-WhiskeyRelativePath)"" to " +
                   "repository ""$($RepositoryName)"": a repository with that name doesn't exist. Update your " +
                   'PublishPowerShellScript task with the name of one of the repository''s that ' +
                   'exists (see above), use the "RepositoryLocation" to specify the URI or path to a repository, ' +
                   'or leave "RepositoryName" blank to publish to the build output directory.'
            }
            else 
            {
                $msg = "Unable to publish PowerShell module ""$($ModuleInfo.ModuleBase | Resolve-WhiskeyRelativePath)"" to " +
                   "repository ""$($RepositoryName)"": a repository with that name doesn't exist. Update your " +
                   'PublishPowerShellModule task with the name of one of the repository''s that ' +
                   'exists (see above), use the "RepositoryLocation" to specify the URI or path to a repository, ' +
                   'or leave "RepositoryName" blank to publish to the build output directory.'
            }

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
        if( $ApiKeyID )
        {
            $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $ApiKeyID -PropertyName 'ApiKeyID'
            if( $apiKey )
            {
                $apiKeyParam['NuGetApiKey'] = $apiKey
            }
        }

        if( -not $infoMsg )
        {
            $infoMsg = "repository ""$($RepositoryName)"" at ""$($RepositoryLocation)"""
        }

        if( $ScriptInfo )
        {
            $msg = "Publishing PowerShell script ""$($Path | Resolve-WhiskeyRelativePath)"" to $($infoMsg)."
        }
        else 
        {
            $msg = "Publishing PowerShell module ""$($Path | Resolve-WhiskeyRelativePath)"" to $($infoMsg)."
        }
        Write-WhiskeyInfo -Context $TaskContext -Message $msg
        Get-Module | Format-Table -AutoSize | Out-String | Write-Debug
        # Use the Force switch to allow publishing versions that come *before* the latest version.
        if( $ScriptInfo )
        {
            Publish-Script -Path $Path -Repository $RepositoryName -Force @apiKeyParam @commonParams -ErrorAction Stop
        }
        else 
        {
            Publish-Module -Path $Path -Repository $RepositoryName -Force @apiKeyParam @commonParams -ErrorAction Stop
        }
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