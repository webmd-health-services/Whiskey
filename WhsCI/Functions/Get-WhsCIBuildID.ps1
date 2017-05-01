
function Get-WhsCIBuildID
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not (Test-Path -Path 'env:BUILD_ID') )
    {
        throw ('Environment variable BUILD_ID does not exist. Are you sure you''re running under a build server? If you see this message while running tests, you most likely need to mock the `ConvertTo-WhsCISemanticVersion` function.')
    }
    (Get-Item -Path 'env:BUILD_ID').Value    
}
