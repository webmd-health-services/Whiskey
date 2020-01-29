
function Write-WhiskeyObject
{
    <#
    .SYNOPSIS
    Writes objects as recognizable strings.

    .DESCRIPTION
    The `Write-WhiskeyObject` function writes objects as recognizable strings. Use the `Level` parameter to control what write function to use (see the help for `Write-WhiskeyInfo` for more information). It supports hashtables and dictionaries. It writes the keys and values in separate columns. If a value contains multiple values, each value is aligned with previous values. For example:

        VERBOSE: [13:34:39.15]
        VERBOSE:     OutputFile    .output\pester.xml
        VERBOSE:     OutputFormat  JUnitXml
        VERBOSE:     PassThru      True
        VERBOSE:     Script        .\PassingTests.ps1
        VERBOSE:                   .\OtherPassingTests.ps1
        VERBOSE:     Show          None
        VERBOSE:     TestName      PassingTests
        VERBOSE: [13:34:39.15]

    .EXAMPLE
    $hashtable | Write-WhiskeyObject -Context $Context -Level Verbose

    Demonstrates how to print the value of a hashtable in a recognizable format. 

    .EXAMPLE
    $hashtable | Write-WhiskeyObject -Level Verbose

    Demonstrates that the `Context` parameter is optional. Whiskey searches up the call stack to find one if you don't pass it.
    #>
    [CmdletBinding()]
    param(
        # The context for the current build. If not provided, Whiskey will search up the call stack looking for it.
        [Whiskey.Context]$Context,

        [ValidateSet('Error','Warning','Info','Verbose','Debug')]
        # The level at which to write the object. The default is `Info`.
        [String]$Level = 'Info',

        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        [AllowNull()]
        [AllowEmptyString()]
        # The message/object to write. Before being written, the message will be prefixed with the duration of the current build and the current task name (if any). If the current duration can't be determined, then the current time is used.
        #
        # If you pipe multiple messages, they are grouped together.
        [Object]$InputObject
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        
        $objects = [Collections.ArrayList]::new()
    }

    process
    {
        $objects.Add($InputObject)
    }

    end
    {
        & {
            foreach( $object in $objects )
            {
                if( $object | Get-Member 'Keys' )
                {
                    $maxKeyLength = $object.Keys | ForEach-Object { $_.ToString().Length } | Sort-Object -Descending | Select-Object -First 1
                    $formatString = '{{0,-{0}}}  {{1}}' -f $maxKeyLength
                    foreach( $key in ($object.Keys | Sort-Object) )
                    {
                        $value = $object[$key]
                        $firstValue = $value | Select-Object -First 1
                        Write-Output ($formatString -f $key,$firstValue)
                        $value | Select-Object -Skip 1 | ForEach-Object { $formatString -f ' ',$_ }
                    }
                }
                else 
                {
                    $object | Out-String
                }
            }
        } | Write-WhiskeyInfo -Context $Context -Level $Level
    }
}
