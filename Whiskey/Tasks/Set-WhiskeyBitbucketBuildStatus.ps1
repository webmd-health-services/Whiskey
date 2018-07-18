
function Set-WhiskeyBitbucketBuildStatus
{
    [CmdletBinding()]
    [Whiskey.Task('PublishBuildStatusToBitbucket')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $TaskContext.ByDeveloper )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message 'SKIPPED: Build status publishing only occurs when build is run by a build server.'
        return
    }

    $uri = $TaskParameter['Uri']
    if( -not $uri )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Uri' -Message @'
Property "Uri" does not exist or does not have a value. Set this property to the Bitbucket Server URI where you want build statuses reported to, e.g.,

    OnBuildStart:
    - PublishBuildStatusToBitbucket:
        Uri: BITBUCKET_SERVER_URI
        CredentialID: CREDENTIAL_ID

'@
        return
    }

    $credentialID = $TaskParameter['CredentialID']
    if( -not $credentialID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'CredentialID' -Message (@'
Property "CredentialID" does not exist or does not have a value. Set this property to the ID of the credential to use when connecting to the Bitbucket Server at "{0}", e.g.,

    OnBuildStart:
    - PublishBuildStatusToBitbucket:
        Uri: {0}
        CredentialID: CREDENTIAL_ID

Use the "Add-WhiskeyCredential" function to add the credential to the build.

'@ -f $uri)
        return
    }

    $buildInfo = $TaskContext.BuildMetadata
    $credential = Get-WhiskeyCredential -Context $TaskContext -ID $credentialID -PropertyName 'CredentialID'
    $bbConnection = New-BBServerConnection -Credential $credential -Uri $uri
    $statusMap = @{
        [Whiskey.BuildStatus]::Started = 'INPROGRESS';
        [Whiskey.BuildStatus]::Succeeded = 'Successful';
        [Whiskey.BuildStatus]::Failed = 'Failed'
    }

    Set-BBServerCommitBuildStatus -Connection $bbConnection -Status $statusMap[$TaskContext.BuildStatus] -CommitID $buildInfo.ScmCommitID -Key $buildInfo.JobUri -BuildUri $buildInfo.BuildUri -Name $buildInfo.JobName
}
