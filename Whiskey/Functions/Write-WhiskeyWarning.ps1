
function Write-WhiskeyWarning
{
    <#
    .SYNOPSIS
    Writes `Warning` level messages.

    .DESCRIPTION
    The `Write-WhiskeyWarning` function writes `Warning` level messages during a build with a prefix that identifies the current build configuration and task being executed.

    Pass the `Whiskey.Context` object to the `Context` parameter and the message to write to the `Message` parameter. Optionally, you may specify a custom indentation level for the message with the `Indent` parameter. The default message indentation is 1 space.

    This function uses PowerShell's [Write-Warning](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-warning) cmdlet to write the message.

    .EXAMPLE
    Write-WhiskeyWarning -Context $context -Message 'A warning message'

    Demonstrates how write a `Warning` message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The current context.
        [Whiskey.Context]$Context,

        [Parameter(Mandatory,ValueFromPipeline)]
        # The message to write.
        [String]$Message,

        [int]$Indent = 0
    )

    Set-StrictMode -Version 'Latest'

    Write-Warning -Message (Format-WhiskeyMessage @PSBoundParameters)
}
