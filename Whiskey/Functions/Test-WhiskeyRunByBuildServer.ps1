
function Test-WhiskeyRunByBuildServer
{
    <#
    .SYNOPSIS
    Tests if the current PowerShell session is running by a build server.

    .DESCRIPTION
    The `Test-WhiskeyRunByBuildServer` checks if the current PowerShell session is running under a build server or not. Currently, only Jenkins is supported. Returns `$true` if running under a build server, `$false` otherwise.
    
    To determine if running under Jenkins, it looks for a `JENKINS_URL` environment variable.

    .EXAMPLE
    Test-WhiskeyRunByBuildServer

    Demonstrates how to use this function. Returns `$true` if running under a build server, `$false` otherwise.
    #>
    [CmdletBinding()]
    param(
    )

    return (Test-Path -Path 'env:JENKINS_URL')
}
