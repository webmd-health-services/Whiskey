
function Publish-WhsCITag
{
    <#
    .SYNOPSIS
    Tags a commit with a Version Tag 

    .DESCRIPTION
    The Publish-WhsCITag function tags a commit with a Version Tag. The commit ID is obtained utilizing the Get-WhsCICommitID funciton. Optionally the user can pass in a Message to add to the Version Tag, or the Force parameter, which will force the commit to be tagged with the Version Tag without considering other commits with similar tags in the Repository.
    
    A WhsCI TaskContext is required as it contains all necessary BBServerConnection information as well as the current Release Version which will be used for the Tag Name
    
    The New-BBServerTag function in the BitbucketServerAutomation Module is called to apply the Tag to the commit.

    .EXAMPLE
    Publish-WhsCITag -TaskContext $context

    Demonstrates how to call Publish-WhsCITag with the default setting of a tag with no message
    
    .EXAMPLE
    Publish-WhsCITag -TaskContext $context -TagMessage 'New Version Tag Message' -Force

    Demonstrates how to call Publish-WhsCITag with an additional Tag Message which will be applied to the Tag
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [String]
        $TagMessage
    )
    
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $TaskContext.Publish -eq $false )
    {
        return
    }

    $uri = Get-Item -Path 'env:GIT_URL'
    $uri = [uri]$uri.Value
    $projectKey = $uri.Segments[1].Trim('/')
    $repoKey = $uri.Segments[2] -replace '\.git$',''
 
    $commitHash = Get-WhsCICommitID
    if( -not $commitHash )
    {
        throw ('Unable to identify a valid commit to tag. Are you sure you''re running under a build server?')
    }

    $optionalArgs = @{}
    if( $TagMessage )
    {
        $optionalArgs['Message'] = $TagMessage
    }

    New-BBServerTag -Connection $TaskContext.BBServerConnection -ProjectKey $projectKey -force -RepositoryKey $repoKey -Name $TaskContext.Version.ReleaseVersion -CommitID $commitHash @optionalArgs

}