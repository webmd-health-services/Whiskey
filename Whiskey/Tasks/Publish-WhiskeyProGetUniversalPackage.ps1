
function Publish-WhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    [Whiskey.Task("PublishProGetUniversalPackage")]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'

    $exampleTask = 'PublishTasks:
        - PublishProGetUniversalPackage:
            CredentialID: ProGetCredential
            Uri: https://proget.example.com
            FeedName: UniversalPackages'


    if( -not $TaskParameter['CredentialID'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet:
        
        $exampleTask
        
        Add credentials to the `Credentials` property on the context returned by `New-WhiskeyContext`, e.g. `$context.Credentials['ProGetCredential'] = `$credential`."
    }
    
    if( -not $TaskParameter['Uri'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "Uri is a mandatory property. It should be the URI to the ProGet instance where you want to publish your package:
        
        $exampleTask
        "
    }

    if( -not $TaskParameter['FeedName'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "FeedName is a mandatory property. It should be the name of the universal feed in ProGet where you want to publish your package:
        
        $exampleTask
        "
    }
    
    $credential = Get-WhiskeyCredential -TaskContext $TaskContext -ID $TaskParameter['CredentialID'] -PropertyName 'CredentialID'

    $session = New-ProGetSession -Uri $TaskParameter['Uri'] -Credential $credential

    if( $TaskParameter.ContainsKey('Path') )
    {
        $packages = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    }
    else
    {
        $packages = Get-ChildItem -Path $TaskContext.OutputDirectory -Filter '*.upack' -ErrorAction Ignore | Select-Object -ExpandProperty 'FullName'
        if( -not $packages )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyDescription '' -Message ('There are no packages to publish in the output directory ''{0}''. By default, the PublishProGetUniversalPackage task publishes all .upack files in the output directory. Check your whiskey.yml file to make sure you''re running the `ProGetUniversalPackage` task before this task (or some other task that creates universal ProGet packages). To publish other .upack files, set this task''s `Path` property to the path to those files.' -f $TaskContext.OutputDirectory)
        }
    }

    $feedName = $TaskParameter['FeedName']
    $taskPrefix = '[{0}]  [{1}]' -f $session.Uri,$feedName
    Write-Verbose -Message ('[PublishProGetUniversalPackage]  {0}' -f $taskPrefix)
    foreach( $package in $packages )
    {
        Write-Verbose -Message ('[PublishProGetUniversalPackage]  {0}  {1}' -f (' ' * $taskPrefix.Length),$package)
        Publish-ProGetUniversalPackage -Session $session -FeedName $feedName -PackagePath $package -ErrorAction Stop
    }
}
