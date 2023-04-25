

function Publish-WhiskeyProGetAsset
{
    [Whiskey.Task('PublishProGetAsset')]
    [Whiskey.RequiresPowerShellModule('ProGetAutomation',
                                        Version='2.*',
                                        VersionParameterName='ProGetAutomationVersion')]
    [CmdletBinding()]
    param(
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        [Whiskey.Context]$TaskContext,

        # The parameters/configuration to use to run the task.
        [hashtable]$TaskParameter,

        [Alias('Uri')]
        [Uri] $Url
    )


    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $message = "
    Build:
    - PublishProGetAsset:
        CredentialID: ProGetCredential
        Path:
        - ""path/to/file.txt""
        - ""path/to/anotherfile.txt""
        Url: http://proget.dev.webmd.com/
        AssetPath:
        - ""path/to/exampleAsset""
        - ""path/toanother/file.txt""
        AssetDirectory: 'versions'
        "
    if( -not $TaskParameter['Path'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Path Parameter to your whiskey.yml file:" + $message)
        return
    }

    if( -not $TaskParameter['AssetDirectory'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory Parameter to your whiskey.yml file:" + $message)
        return
    }

    if( -Not $TaskParameter['CredentialID'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet. Add the credential with the `Add-WhiskeyCredential` function:" + $message)
        return
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'

    $session = New-ProGetSession -Uri $Url -Credential $credential -WarningAction Ignore

    $assetDirName = $TaskParameter['AssetDirectory']
    Write-WhiskeyInfo $Url
    foreach($path in $TaskParameter['Path'])
    {
        if( $TaskParameter['AssetPath'] -and @($TaskParameter['AssetPath']).count -eq @($TaskParameter['Path']).count){
            $name = @($TaskParameter['AssetPath'])[$TaskParameter['Path'].indexOf($path)]
        }
        else
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ("There must be the same number of `Path` items as `AssetPath` Items. Each asset must have both a `Path` and an `AssetPath` in the whiskey.yml file." + $message)
            return
        }

        Write-WhiskeyInfo "  $($path | Resolve-WhiskeyRelativePath) -> ${assetDirName}/${name}"
        Set-ProGetAsset -Session $session -DirectoryName $assetDirName -Path $name -FilePath $path
    }
}