
function Write-WhiskeyInfo
{
    <#
    .SYNOPSIS
    Writes `Info` level messages.

    .DESCRIPTION
    The `Write-WhiskeyInfo` function writes `Info` level messages during a build with a prefix that identifies the current pipeline and task being executed.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. Optionally, you may specify a custom indentation level for the message with the `Indent` parameter. The default message indentation is 1 space.

    This function uses PowerShell's [Write-Information](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-information) cmdlet to write the message. If `Write-Information` is not supported, e.g. below PowerShell 5.0, the function falls back to using [Write-Output](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-output).

    .EXAMPLE
    Write-WhiskeyInfo -Context $context -Message 'An info message'

    Demonstrates how write an `Info` message.

    .EXAMPLE
    Write-WhiskeyInfo -Context $context -Message 'An info message' -Indent 2

    Demonstrates how write an `Info` message with a custom indent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline)]
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

        $Message = Format-WhiskeyMessage @PSBoundParameters
        if( $supportsWriteInformation )
        {
            Write-Information -MessageData $Message -InformationAction Continue
        }
        else
        {
            Write-Output -InputObject $Message
        }
    }
}
