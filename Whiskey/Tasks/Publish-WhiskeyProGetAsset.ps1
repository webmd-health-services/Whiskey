

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
        * `Name`: The desired Name you wish the file to be named in ProGet. Defaults to file name at end of Path Parameter if not provided otherwise the number of names provided must equal the number of file paths.
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

        Example of adding an asset named `exampleAsset` to ProGet in the `versions` directory.     
        
        ### Example 2
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Directory: 'versions/subdirectory'

        Example of adding an asset named `file.txt` to ProGet in the `versions/subdirectory` directory.     


        ### Example 3
        BuildTasks:
        - PublishProGetAsset:
            CredentialID: ProGetCredential
            ApiKeyID: ProGetApiKey
            Path: 
            - 'path/to/file.txt'
            - 'Path/to/anotherfile.txt'
            Uri: http://proget.dev.webmd.com/
            Directory: 'versions/subdirectory'

        Example of adding two assets named `file.txt` and `anotherfile.txt` to ProGet in the `versions/subdirectory` directory.     

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

    if( -not $TaskParameter['Path'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Path Parameter to your whiskey.yml file: 
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
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory Parameter to your whiskey.yml file'
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

    foreach($path in $TaskParameter['Path']){
        if( $TaskParameter['Name'] -and @($TaskParameter['Name']).count -eq @($TaskParameter['Path']).count){
            $Name = $TaskParameter['Name'][$TaskParameter['Path'].indexOf($path)]
        }
        else
        {
            $Name = (Split-Path -Path $path -Leaf)
        }
        Set-ProGetAsset -Session $session -Directory $TaskParameter['Directory'] -Name $Name -Path $path
    }
}