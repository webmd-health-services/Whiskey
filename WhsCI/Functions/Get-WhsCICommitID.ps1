
function Get-WhsCICommitID
{
    <#
    .SYNOPSIS
    Returns the current git commit ID.

    .DESCRIPTION
    The Get-WhsCICommitID function returns the first seven characters of the commit ID contained within the Jenkins environment variable GIT_COMMIT. As such, you must be running on the build server else an error will be thrown.

    .EXAMPLE
    $commitHash = Get-WhsCICommitID

    Demonstrates how to call Get-WhsCICommitID in the default manner to obtain and store a commit ID.
    #>
    [CmdletBinding()]
    param(
    )
    
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $commitID = $null
    if( (Test-WhsCIRunByBuildServer) )
    {
        if( -not (Test-Path -Path 'env:GIT_COMMIT') )
        {
            throw ('Environment variable GIT_COMMIT does not exist. Are you sure you''re running under a build server? If you see this message while running tests, you most likely need to mock the `Get-WhsCICommitID` function.')
        }
        $commitID = (Get-Item -Path 'env:GIT_COMMIT').Value.Substring(0,7)
    }
    else
    {
        Write-Error ('CommitID is not accessible unless you are running under a build server.')
    }
    return $commitID
}