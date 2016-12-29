
function Invoke-WhsCIPowerShellTask
{
    <#
    .SYNOPSIS
    Runs PowerShell commands.

    .DESCRIPTION
    The `Invoke-WhsCIPowerShellTask` runs PowerShell scripts. Pass the path to the script to the `ScriptPath` parameter. IF the script exists with a non-zero exit code, the task fails (i.e. throws a terminating exception/error).

    .EXAMPLE
    Invoke-WhsCIPowerShellTask -ScriptPath '.\mytask.ps1'

    Demonstrates how to use the `Invoke-WhsCIPowerShellTask` function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The script to run. 
        $ScriptPath,

        [string]
        # The directory the script should be executed in. Defaults to the current working directory.
        $WorkingDirectory = (Get-Location).ProviderPath
    )

    Set-StrictMode -Version 'Latest'

    if( -not (Test-Path -Path $WorkingDirectory -PathType Container) )
    {
        throw ('Can''t run PowerShell script ''{0}'': working directory ''{1}'' doesn''t exist.' -f $ScriptPath,$WorkingDirectory)
    }

    Push-Location $WorkingDirectory
    try
    {
        $Global:LASTEXITCODE = 0
        & $ScriptPath
        if( $Global:LASTEXITCODE )
        {
            throw ('PowerShell script ''{0}'' failed, exiting with code {1}.' -F $ScriptPath,$LastExitCode)
        }
    }
    finally
    {
        Pop-Location
    }
}