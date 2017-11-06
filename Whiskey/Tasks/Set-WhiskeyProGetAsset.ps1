

function Set-WhiskeyProGetAsset {
    <#
        .SYNOPSIS
        Adds and Updates assets to the ProGet asset manager. 

        .DESCRIPTION
        The `Set-WhiskeyProGetAsset` adds assets to ProGet. A root directory needs to be 
        created in ProGet using the `New-ProGetFeed` function in ProGetAutomation with Type `Asset`.
        
        * `Path` (Mandatory): The relative paths to the files/directories to upload to ProGet. Paths should be relative to the whiskey.yml file they were taken from.
        * `Uri` (Mandatory): The uri to the ProGet instance.
        * `Name` (Mandatory): The desired Name you wish the file to be named in ProGet.
        * `Directory` (Mandatory): The Path to the Directory you wish to upload the asset to.
        * `ApiKey` (Mandatory): The ApiKey to Proget Api.
        * `ProGetUsername` (Mandatory): The Username to the ProGet Api.
        * `ProGetPassword` (Mandatory): The Password to the ProGet Api.

        .EXAMPLE       
        BuildTasks:
        - SetProGetAsset:
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ApiKey: 'exampleApiKey'
            ProGetUsername: Admin
            ProGetPassword: Admin

        Example of adding an asset to ProGet in the versions directory.      
    #>
    [Whiskey.Task("SetProGetAsset",SupportsClean=$true)]
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
        - SetProGetAsset:
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ApiKey: 'exampleApiKey'
            ProGetUsername: Admin
            ProGetPassword: Admin
            ")
    }

    if( -not $TaskParameter['Directory'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add a valid Directory to your whiskey.yml file'
        BuildTasks:
        - SetProGetAsset:
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ApiKey: 'exampleApiKey'
            ProGetUsername: Admin
            ProGetPassword: Admin")
    }

    if( -not $TaskParameter['ApiKey'] -or  -not $TaskParameter['ProGetUsername'] -or -not $TaskParameter['ProGetPassword'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ("Please add valid ProGet credentials and ApiKey to your whiskey.yml file
        BuildTasks:
        - SetProGetAsset:
            Path: 'path/to/file.txt'
            Uri: http://proget.dev.webmd.com/
            Name: 'exampleAsset'
            Directory: 'versions'
            ApiKey: 'exampleApiKey'
            ProGetUsername: Admin
            ProGetPassword: Admin")
    }

    $credential = New-Credential -UserName $TaskParameter['ProGetUsername'] -Password $TaskParameter['ProGetPassword']
    $session = New-ProGetSession -Uri $TaskParameter['Uri'] -Credential $credential -ApiKey $TaskParameter['ApiKey']

    Set-ProGetAsset -Session $session -Directory $TaskParameter['Directory'] -Name $TaskParameter['Name'] -Path $TaskParameter['Path']

}