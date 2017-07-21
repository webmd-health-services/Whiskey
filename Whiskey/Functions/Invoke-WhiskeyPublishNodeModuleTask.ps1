
function Invoke-WhiskeyPublishNodeModuleTask
{
    <#
    .SYNOPSIS
    Publishes a Node module package to the target NPM registry
    
    .DESCRIPTION
    The `Invoke-WhiskeyPublishNodeModuleTask` function utilizes NPM's `publish` command to publish Node module packages.

    You are required to specify what version of Node.js you want in the engines field of your package.json file. (See https://docs.npmjs.com/files/package.json#engines for more information.) The version of Node is installed for you using NVM. 

    This task accepts these parameters:

    * `WorkingDirectory`: the directory where the NPM publish command will be run. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.
    
    .EXAMPLE
    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $context -TaskParameter @{}

    Demonstrates how to `publish` the Node module package located in the directory specified by the `$context.BuildRoot` property. The function would run `npm publish`.

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $context -TaskParameter @{ WorkingDirectory = '\PathToPackage\RelativeTo\whiskey.yml' }

    Demonstrates how to `publish` the Node module package located in the directory specified by the `WorkingDirectory` property. The function would run `npm publish`.
    #>
    [Whiskey.Task("PublishNodeModule")]
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
        $TaskParamete
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $buildRoot = $TaskContext.BuildRoot
    $workingDir = $buildRoot
    if($TaskParameter.ContainsKey('WorkingDirectory'))
    {
        $workingDir = $TaskParameter['WorkingDirectory'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory'
    }

    $npmRegistryUri = $TaskParameter['npmRegistryUri']
    if (-not $npmRegistryUri) 
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property ''NpmRegistryUri'' is mandatory. It should be the URI to the registry where the module should be published. E.g.,
        
        BuildTasks:
        - PublishNodeModule:
            NpmRegistryUri: https://registry.npmjs.org/
        '
    }
    $nodePath = Install-WhiskeyNodeJs -RegistryUri $npmRegistryUri -ApplicationRoot $workingDir
    
    if (!$TaskContext.Publish)
    {
        return
    }
    
    $nodeRoot = $nodePath | Split-Path
    $npmPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js' -Resolve

    $npmConfigPrefix = '//{0}{1}:' -f $npmregistryUri.Authority,$npmRegistryUri.LocalPath

    $npmUserName = $TaskContext.ProGetSession.Credential.UserName
    $npmEmail = $env:USERNAME + '@example.com'
    $npmCredPassword = $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)

    Push-Location $workingDir
    try
    {
        $packageNpmrc = (New-Item -Path (Join-Path -Path $buildRoot -ChildPath '.npmrc') -ItemType File -Force)
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
    
        Invoke-Command -ScriptBlock {
            & $nodePath $npmPath publish
        }
    }
    finally
    {
        if (Test-Path $packageNpmrc)
        {
            Write-Verbose -Message ('Removing .npmrc at {0}.' -f $packageNpmrc)
            Remove-Item -Path $packageNpmrc
        }
        Pop-Location
    }
}


