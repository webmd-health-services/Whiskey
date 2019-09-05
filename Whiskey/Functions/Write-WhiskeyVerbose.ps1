
function Write-WhiskeyVerbose
{
    <#
    .SYNOPSIS
    Writes `Verbose` level messages.

    .DESCRIPTION
    The `Write-WhiskeyVerbose` function writes `Verbose` level messages during a build with a prefix that identifies the current pipeline and task being executed.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. Optionally, you may specify a custom indentation level for the message with the `Indent` parameter. The default message indentation is 1 space.

    This function uses PowerShell's [Write-Verbose](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-verbose) cmdlet to write the message.

    .EXAMPLE
    Write-WhiskeyVerbose -Context $context -Message 'A verbose message'

    Demonstrates how write a `Verbose` message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [AllowEmptyString()]
        [AllowNull()]
        # The message to write.
        [string]$Message,

        [int]$Indent = 0
    )

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
        Write-Verbose -Message (Format-WhiskeyMessage @PSBoundParameters)
    }
}
