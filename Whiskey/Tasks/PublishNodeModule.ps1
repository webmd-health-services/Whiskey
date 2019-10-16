
function Publish-WhiskeyNodeModule
{
    [Whiskey.Task("PublishNodeModule")]
    [Whiskey.RequiresTool("Node", "NodePath", VersionParameterName='NodeVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [string]$CredentialID,

        [string]$EmailAddress,

        [uri]$NpmRegistryUri,

        [string]$Tag
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if (-not $NpmRegistryUri) 
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property ''NpmRegistryUri'' is mandatory and must be a URI. It should be the URI to the registry where the module should be published. E.g.,
        
    Build:
    - PublishNodeModule:
        NpmRegistryUri: https://registry.npmjs.org/
    '
        return
    }

    if( -not $CredentialID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''CredentialID'' is mandatory. It should be the ID of the credential to use when publishing to ''{0}'', e.g.
    
    Build:
    - PublishNodeModule:
        NpmRegistryUri: {0}
        CredentialID: NpmCredential
    
    Use the `Add-WhiskeyCredential` function to add the credential to the build.
    ' -f $NpmRegistryUri)
        return
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $CredentialID -PropertyName 'CredentialID'
    $npmUserName = $credential.UserName
    if( -not $EmailAddress )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''EmailAddress'' is mandatory. It should be the e-mail address of the user publishing the module, e.g.
    
    Build:
    - PublishNodeModule:
        NpmRegistryUri: {0}
        CredentialID: {1}
        EmailAddress: somebody@example.com
    ' -f $NpmRegistryUri,$CredentialID)
        return
    }

    $npmConfigPrefix = '//{0}{1}:' -f $NpmRegistryUri.Authority,$NpmRegistryUri.LocalPath
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)

    $originalPackageJsonPath = Resolve-Path -Path 'package.json' | Select-Object -ExpandProperty 'ProviderPath'
    $backupPackageJsonPath = Join-Path -Path $TaskContext.Temp -ChildPath 'package.json'

    try
    {
        $packageNpmrc = New-Item -Path '.npmrc' -ItemType File -Force
        Add-Content -Path $packageNpmrc -Value ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
        Add-Content -Path $packageNpmrc -Value ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
        Add-Content -Path $packageNpmrc -Value ('{0}email={1}' -f $npmConfigPrefix, $EmailAddress)
        Add-Content -Path $packageNpmrc -Value ('registry={0}' -f $NpmRegistryUri)
        Write-WhiskeyVerbose -Context $TaskContext -Message ('Creating .npmrc at {0}.' -f $packageNpmrc)
        Get-Content -Path $packageNpmrc |
            ForEach-Object {
                if( $_ -match '_password' )
                {
                    return $_ -replace '=(.*)$','=********'
                }
                return $_
            } |
            Write-WhiskeyVerbose -Context $TaskContext


        Copy-Item -Path $originalPackageJsonPath -Destination $backupPackageJsonPath
        Invoke-WhiskeyNpmCommand -Name 'version' `
                                -ArgumentList $TaskContext.Version.SemVer2NoBuildMetadata, '--no-git-tag-version', '--allow-same-version' `
                                -BuildRootPath $TaskContext.BuildRoot `
                                -ErrorAction Stop

        Invoke-WhiskeyNpmCommand -Name 'prune' -ArgumentList '--production' -BuildRootPath $TaskContext.BuildRoot -ErrorAction Stop

        $publishArgumentList = @(
            if( $Tag )
            {
                '--tag'
                $Tag
            }
            elseif( $TaskContext.Version.SemVer2.Prerelease )
            {
                '--tag'
                Resolve-WhiskeyVariable -Context $TaskContext -Name 'WHISKEY_SEMVER2_PRERELEASE_ID'
            }
        )

        Invoke-WhiskeyNpmCommand -Name 'publish' -ArgumentList $publishArgumentList -BuildRootPath $TaskContext.BuildRoot -ErrorAction Stop
    }
    finally
    {
        if (Test-Path -Path $packageNpmrc -PathType Leaf)
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('Removing .npmrc at {0}.' -f $packageNpmrc)
            Remove-Item -Path $packageNpmrc
        }

        if (Test-Path -Path $backupPackageJsonPath -PathType Leaf)
        {
            Copy-Item -Path $backupPackageJsonPath -Destination $originalPackageJsonPath -Force
        }
    }
}
