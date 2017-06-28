
function Get-WhiskeyBranch
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not (Test-Path -Path 'env:GIT_BRANCH') )
    {
        throw ('Environment variable GIT_BRANCH does not exist. Are you sure you''re running under a build server? If you see this message while running tests, you most likely need to mock the `ConvertTo-WhiskeySemanticVersion` function.')
    }
    (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
}

