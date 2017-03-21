
function Invoke-WhsCIPublishNodeModuleTask
{
    <#
    .SYNOPSIS
    Publishes a Node module package to the target NPM registry
    
    .DESCRIPTION
    The `Invoke-WhsCIPublishNodeModuleTask` function utilizes NPM's `publish` command to publish Node module packages.

    You are required to specify what version of Node.js you want in the engines field of your package.json file. (See https://docs.npmjs.com/files/package.json#engines for more information.) The version of Node is installed for you using NVM. 

    This task accepts these parameters:

    * `WorkingDirectory`: the directory where the NPM publish command will be run. Defaults to the directory where the build's `whsbuild.yml` file was found. Must be relative to the `whsbuild.yml` file.
    
    .EXAMPLE
    Invoke-WhsCIPublishNodeModuleTask -TaskContext $context -TaskParameter @{}

    Demonstrates how to `publish` the Node module package located in the directory specified by the `$context.BuildRoot` property. The function would run `npm publish`.

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $context -TaskParameter @{ WorkingDirectory = '\PathToPackage\RelativeTo\WhsBuild.yml' }

    Demonstrates how to `publish` the Node module package located in the directory specified by the `WorkingDirectory` property. The function would run `npm publish`.
    #>
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
        # * `WorkingDirectory` (Optional): Provides the default root directory for the NPM `publish` task. Defaults to the directory where the build's `whsbuild.yml` file was found. Must be relative to the `whsbuild.yml` file.                     
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $buildRoot = $TaskContext.BuildRoot
    $workingDir = $buildRoot
    if($TaskParameter.ContainsKey('WorkingDirectory'))
    {
        $workingDir = $TaskParameter['WorkingDirectory'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory'
    }
    [String]$npmFeedUri = $TaskContext.ProGetSession.NpmFeedUri
    $nodePath = Install-WhsCINodeJs -RegistryUri $npmFeedUri -ApplicationRoot $workingDir
    $nodeRoot = $nodePath | Split-Path
    $npmPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js' -Resolve

    if (!$TaskContext.Publish)
    {
        return
    }

    $npmConfigPrefix = $npmFeedUri.SubString($npmFeedUri.IndexOf(':') + 1, $npmFeedUri.Length - ($npmFeedUri.IndexOf(':') + 1))
    $npmConfigPrefix = $npmConfigPrefix.Substring(0, $npmConfigPrefix.LastIndexOf('/') + 1)

    $npmUserName = $TaskContext.ProGetSession.Credential.UserName
    $npmEmail = 'jenkins@webmd.net'
    $npmCredPassword = $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)

    Push-Location $workingDir
    try
    {
        $packageNpmrc = (New-Item -Path (Join-Path -Path $buildRoot -ChildPath '.npmrc') -ItemType File -Force)
        Add-Content -Path $packageNpmrc -Value ('registry={0}' -f $npmFeedUri)
        Add-Content -Path $packageNpmrc -Value ('{0}:_password="{1}"' -f $npmConfigPrefix, $npmPassword)
        Add-Content -Path $packageNpmrc -Value ('{0}:username={1}' -f $npmConfigPrefix, $npmUserName)
        Add-Content -Path $packageNpmrc -Value ('{0}:email={1}' -f $npmConfigPrefix, $npmEmail)
    
        Invoke-Command -ScriptBlock {
            & $nodePath $npmPath publish
        }
    }
    finally
    {
        if (Test-Path $packageNpmrc)
        {
            Remove-Item $packageNpmrc
        }
        Pop-Location
    }
}
