
function Get-WhiskeyCommitID
{
    <#
    .SYNOPSIS
    Returns the current git commit ID.

    .DESCRIPTION
    The Get-WhiskeyCommitID function returns the first seven characters of the commit ID contained within the Jenkins environment variable GIT_COMMIT. As such, you must be running on the build server else an error will be thrown.

    .EXAMPLE
    $commitHash = Get-WhiskeyCommitID

    Demonstrates how to call Get-WhiskeyCommitID in the default manner to obtain and store a commit ID.
    #>
    [CmdletBinding()]
    param(
    )
    
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $commitID = $null

    if( -not (Test-Path -Path 'env:GIT_COMMIT') )
    {
        throw ('Environment variable GIT_COMMIT does not exist. Are you sure you''re running under a build server? If you see this message while running tests, you most likely need to mock the `Get-WhiskeyCommitID` function.')
    }
    $commitID = (Get-Item -Path 'env:GIT_COMMIT').Value.Substring(0,7)
    return $commitID
}
