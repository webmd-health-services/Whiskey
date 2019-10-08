
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

        [uri]$NpmRegistryUri
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

    if (!$TaskContext.Publish)
    {
        return
    }
    
    $npmConfigPrefix = '//{0}{1}:' -f $NpmRegistryUri.Authority,$NpmRegistryUri.LocalPath

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
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)

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

        Invoke-WhiskeyNpmCommand -Name 'prune' -ArgumentList '--production' -BuildRootPath $TaskContext.BuildRoot -ErrorAction Stop
        Invoke-WhiskeyNpmCommand -Name 'publish' -BuildRootPath $TaskContext.BuildRoot -ErrorAction Stop
    }
    finally
    {
        if (Test-Path $packageNpmrc)
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('Removing .npmrc at {0}.' -f $packageNpmrc)
            Remove-Item -Path $packageNpmrc
        }
    }
}
