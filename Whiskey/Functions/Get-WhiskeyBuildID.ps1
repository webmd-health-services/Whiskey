
function Get-WhiskeyBuildID
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not (Test-Path -Path 'env:BUILD_ID') )
    {
        throw ('Environment variable BUILD_ID does not exist. Are you sure you''re running under a build server?')
    }
    (Get-Item -Path 'env:BUILD_ID').Value    
}

