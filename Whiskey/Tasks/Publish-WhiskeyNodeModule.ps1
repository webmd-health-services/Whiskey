
function Publish-WhiskeyNodeModule
{
    <#
    .SYNOPSIS
    Publishes a Node module package to the target NPM registry
    
    .DESCRIPTION
    The `PublishNodeModule` task runs `npm publish` in the current working directory.

    This task will install the latest LTS version of Node into a `.node` directory (in the same directory as your whiskey.yml file). To use a specific version, set the `engines.node` property in your package.json file to the version you want. (See https://docs.npmjs.com/files/package.json#engines for more information.)

    # Properties
    

    * `WorkingDirectory`: the directory where the NPM publish command will be run. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.
    
    # Examples
    
    ## Example 1
    
        BuildTasks:
	- PublishNodeModule

    Demonstrates how to publish the Node module located in the same directory as your whiskey.yml file
    
    ## Example 2
    
    	BuildTasks:
	- PublishNodeModule:
    	    WorkingDirectory: 'app'

    Demonstrates how to publish a Node module that isn't in the same directory as your whiskey.yml file. In this example, the Node moule in the `app` directory is published (`app` is resolved relative to your whiskey.yml file).
    #>
    [Whiskey.Task("PublishNodeModule")]
    [Whiskey.RequiresTool("Node", "NodePath")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context the task is running under.
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # The parameters/configuration to use to run the task. Should be a hashtable that contains the following item:
        #
        # * `WorkingDirectory` (Optional): Provides the default root directory for the NPM `publish` task. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.                     
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $workingDirectory = (Get-Location).ProviderPath

    $npmRegistryUri = [uri]$TaskParameter['NpmRegistryUri']
    if (-not $npmRegistryUri) 
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property ''NpmRegistryUri'' is mandatory and must be a URI. It should be the URI to the registry where the module should be published. E.g.,
        
    BuildTasks:
    - PublishNodeModule:
        NpmRegistryUri: https://registry.npmjs.org/
    '
    }

    if (!$TaskContext.Publish)
    {
        return
    }
    
    $npmConfigPrefix = '//{0}{1}:' -f $npmregistryUri.Authority,$npmRegistryUri.LocalPath

    $credentialID = $TaskParameter['CredentialID']
    if( -not $credentialID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''CredentialID'' is mandatory. It should be the ID of the credential to use when publishing to ''{0}'', e.g.
    
    BuildTasks:
    - PublishNodeModule:
        NpmRegistryUri: {0}
        CredentialID: NpmCredential
    
    Use the `Add-WhiskeyCredential` function to add the credential to the build.
    ' -f $npmRegistryUri)
    }
    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $credentialID -PropertyName 'CredentialID'
    $npmUserName = $credential.UserName
    $npmEmail = $TaskParameter['EmailAddress']
    if( -not $npmEmail )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''EmailAddress'' is mandatory. It should be the e-mail address of the user publishing the module, e.g.
    
    BuildTasks:
    - PublishNodeModule:
        NpmRegistryUri: {0}
        CredentialID: {1}
        EmailAddress: somebody@example.com
    ' -f $npmRegistryUri,$credentialID)
    }
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)

    try
    {
        $packageNpmrc = New-Item -Path '.npmrc' -ItemType File -Force
        Add-Content -Path $packageNpmrc -Value ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
        Add-Content -Path $packageNpmrc -Value ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
        Add-Content -Path $packageNpmrc -Value ('{0}email={1}' -f $npmConfigPrefix, $npmEmail)
        Write-Verbose -Message ('Creating .npmrc at {0}.' -f $packageNpmrc)
        Get-Content -Path $packageNpmrc |
            ForEach-Object {
                if( $_ -match '_password' )
                {
                    return $_ -replace '=(.*)$','=********'
                }
                return $_
            } |
            Write-Verbose

        $nodePath = $TaskParameter['NodePath']
        $npmPath = Get-WhiskeyNPMPath -NodePath $nodePath
        Write-Verbose -Message 'Removing extraneous packages with ''npm prune'''
        Invoke-Command -ScriptBlock {
            & $nodePath $npmPath prune --production --no-color
        }
        
        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NPM command ''npm prune'' failed with exit code ''{0}''.' -f $LASTEXITCODE)
        }
        
        Write-Verbose -Message 'Publishing package with ''npm publish'''
        Invoke-Command -ScriptBlock {
            & $nodePath $npmPath publish
        }
        
        if ($LASTEXITCODE -ne 0)
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NPM command ''npm publish'' failed with exit code ''{0}''.' -f $LASTEXITCODE)
        }
    }
    finally
    {
        if (Test-Path $packageNpmrc)
        {
            Write-Verbose -Message ('Removing .npmrc at {0}.' -f $packageNpmrc)
            Remove-Item -Path $packageNpmrc
        }
    }
}
