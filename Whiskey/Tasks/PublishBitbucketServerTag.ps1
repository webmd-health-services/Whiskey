
function Publish-WhiskeyBBServerTag
{
    [CmdletBinding()]
    [Whiskey.Task('PublishBitbucketServerTag')]
    [Whiskey.RequiresPowerShellModule('BitbucketServerAutomation', Version='0.9.*',
        VersionParameterName='BitbucketServerAutomationVersion')]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Alias('Uri')]
        [Uri] $Url,

        [String] $CredentialID,

        [String] $ProjectKey,

        [String] $RepositoryKey
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $exampleTask = 'Publish:
        - PublishBitbucketServerTag:
            CredentialID: BitbucketServerCredential
            Url: https://bitbucketserver.example.com'

    if( $TaskContext.BuildMetadata.IsPullRequest )
    {
        'Skipping PublishBitbucketServerTag task: can''t tag a pull request commit because it doesn''t exist in the ' +
        'origin repostory, only on the build server.' | Write-WhiskeyVerbose
        return
    }

    if (-not $CredentialID)
    {
        $msg = 'Property "CredentialID" is mandatory. It should be the ID of the credential to use when connecting ' +
               "to Bitbucket Server:

        ${exampleTask}

        Use the `Add-WhiskeyCredential` function to add credentials to the build.
        "

        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if (-not $Url)
    {
        $msg = 'Property "Url" is mandatory. It should be the URL to the instance of Bitbucket Server where the ' +
               "tag should be created:

        ${exampleTask}
        "
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $commitHash = $TaskContext.BuildMetadata.ScmCommitID
    if( -not $commitHash )
    {
        $msg = 'Unable to identify a valid commit to tag. Are you sure you''re running under a build server?'
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyDescription '' -Message $msg
        return
    }

    if ($ProjectKey -and $RepositoryKey)
    {
        $projectKey = $ProjectKey
        $repoKey = $RepositoryKey
    }
    elseif ($TaskContext.BuildMetadata.ScmUri -and $TaskContext.BuildMetadata.ScmUri.Segments)
    {
        $scmUrl = [Uri]$TaskContext.BuildMetadata.ScmUri
        $projectKey = $scmUrl.Segments[-2].Trim('/')
        $repoKey = $scmUrl.Segments[-1] -replace '\.git$',''
    }
    else
    {
        $msg = 'Unable to determine the repository where we should create the tag. Either create a `GIT_URL` ' +
               'environment variable that is the URL used to clone your repository, or add your repository''s ' +
               'project and repository keys as `ProjectKey` and `RepositoryKey` properties, respectively, on this ' +
               "task:
" + '  ' + "
    Publish:
    - PublishBitbucketServerTag:
        CredentialID: ${CredentialID}
        Url: ${Url}
        ProjectKey: PROJECT_KEY
        RepositoryKey: REPOSITORY_KEY
        "
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyDescription '' -Message $msg
        return
    }

    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $CredentialID -PropertyName 'CredentialID'
    $connection = New-BBServerConnection -Credential $credential -Uri $Url
    $tag = $TaskContext.Version.SemVer2NoBuildMetadata
    $msg = "Tagging commit ""$($commitHash)"" with ""$($tag)"" in Bitbucket Server ""$($projectKey)"" project's " +
           """$($repoKey)"" repository at ${Url}."
    Write-WhiskeyInfo $msg
    New-BBServerTag -Connection $connection `
                    -ProjectKey $projectKey `
                    -Force `
                    -RepositoryKey $repoKey `
                    -Name $tag `
                    -CommitID $commitHash `
                    -ErrorAction Stop
}
