

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
        * `Name` (Mandatory): The desired Name you wish the file to be named in ProGet.
        * `Directory` (Mandatory): The Path to the Directory you wish to upload the asset to.

        ## Examples
        
        ### Example 1
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'

        Example of adding an asset to ProGet in the versions directory.      
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

    if( -not $TaskParameter['Name'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Name to your whiskey.yml file: 
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ")
    }

    if( -not $TaskParameter['Directory'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory to your whiskey.yml file'
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ")
    }

    if( -Not $TaskParameter['CredentialID'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet:
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ")
    }

    if( -Not $TaskParameter['ApiKeyID'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("ApiKeyID is a mandatory property. It should be the ID of the ApiKey to use when connecting to ProGet:
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ")
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'
    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $TaskParameter['ApiKeyID'] -PropertyName 'ApiKeyID'

    $session = New-ProGetSession -Uri $TaskParameter['Uri'] -Credential $credential -ApiKey $apiKey
    
    Set-ProGetAsset -Session $session -Directory $TaskParameter['Directory'] -Name $TaskParameter['Name'] -Path $TaskParameter['Path']

}