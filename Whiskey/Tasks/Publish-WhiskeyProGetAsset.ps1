

function Publish-WhiskeyProGetAsset
{
    <#
        .SYNOPSIS
        Publishes assets to ProGet. 

        .DESCRIPTION
        The `PublishProGetAsset` task adds assets to ProGet. A root directory needs to be 
        created in ProGet using the `New-ProGetFeed` function in ProGetAutomation with Type `Asset`.
        
        ## Properties
        * `CredentialID`: The ID to the ProGet Credential. Set the `CredentialID` property to the ID of the credential to use when uploading. Add the credential with the `Add-WhiskeyCredential` function.
        * `ApiKeyID` (Mandatory): The ID to the  ApiKey to the ProGet Api. Use the `Add-WhiskeyApiKey` to add your API key.
        * `Path` (Mandatory): The relative paths to the files/directories to upload to ProGet. Paths should be relative to the whiskey.yml file they were taken from.
        * `Uri` (Mandatory): The uri to the ProGet instance.
        * `AssetPath` (Mandatory): The desired Paths to the location you wish the file to be uploaded to in ProGet. The last item in the path is the asset name. The number of names provided must equal the number of file paths.
        * `AssetDirectory` (Mandatory): The root asset Directory you wish to upload the asset to.

        ## Examples
        
        ### Example 1
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            AssetPath: 'exampleAsset'
            AssetDirectory: 'versions'

        Example of adding an asset named `exampleAsset` to ProGet in the `versions` directory.       

        ### Example 2
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 
            - 'path/to/file.txt'
            - 'Path/to/anotherfile.txt'
            Uri: http://proget.dev.webmd.com/
            AssetPath: 
            - 'asset/path/file.txt'
            - 'asset/anotherfile.txt'
            AssetDirectory: 'exampleDirectory'

        Example of adding two assets named `file.txt` and `anotherfile.txt` to ProGet in the `exampleDirectory/asset/path` and `exampleDirectory/asset` directories respectively.     

    #>
    [Whiskey.Task("PublishProGetAsset")]
    [CmdletBinding()]
    param(
        [object]
        # The context this task is operating in. Use `New-WhiskeyContext` to create context objects.
        $TaskContext,
        
        [hashtable]
        # The parameters/configuration to use to run the task.
        $TaskParameter
    )


    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $message = "
    BuildTasks:
    - PublishProGetAsset:
        CredentialID: ProGetCredential
        ApiKeyID: ProGetApiKey
        Path: 
        -'path/to/file.txt'
        -'path/to/anotherfile.txt'
        Uri: http://proget.dev.webmd.com/
        AssetPath: 
        -'path/to/exampleAsset'
        -'path/toanother/file.txt'
        AssetDirectory: 'versions'
        "
    if( -not $TaskParameter['Path'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Path Parameter to your whiskey.yml file:" + $message)
    }

    if( -not $TaskParameter['AssetDirectory'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory Parameter to your whiskey.yml file:" + $message)
    }

    if( -Not $TaskParameter['CredentialID'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet. Add the credential with the `Add-WhiskeyCredential` function:" + $message)
    }

    if( -Not $TaskParameter['ApiKeyID'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("ApiKeyId is a mandatory property. It should be the ID of the ApiKey to use when connecting to ProGet.  Use the `Add-WhiskeyApiKey` to add your API key.:"+$message)
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'
    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $TaskParameter['ApiKeyID'] -PropertyName 'ApiKeyID'

    $session = New-ProGetSession -Uri $TaskParameter['Uri'] -Credential $credential -ApiKey $apiKey

    foreach($path in $TaskParameter['Path']){
        if( $TaskParameter['AssetPath'] -and @($TaskParameter['AssetPath']).count -eq @($TaskParameter['Path']).count){
            $name = $TaskParameter['AssetPath'][$TaskParameter['Path'].indexOf($path)]
        }
        else
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ("There must be the same number of `Path` items as `AssetPath` Items. Each asset must have both a `Path` and an `AssetPath` in the whiskey.yml file." + $message)
        }
        Set-ProGetAsset -Session $session -DirectoryName $TaskParameter['AssetDirectory'] -Path $name -FilePath $path
    }
}