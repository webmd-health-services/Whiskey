
function Get-WhiskeyTask
{
    <#
    .SYNOPSIS
    Returns a list of available Whiskey tasks.

    .DESCRIPTION
    The `Get-WhiskeyTask` function returns a list of all available Whiskey tasks. Obsolete tasks are not returned. If you also want obsolete tasks returned, use the `-Force` switch.

    .EXAMPLE
    Get-WhiskeyTask

    Demonstrates how to get a list of all non-obsolete Whiskey tasks.

    .EXAMPLE
    Get-WhiskeyTask -Force

    Demonstrates how to get a list of all Whiskey tasks, including those that are obsolete.
    #>
    [CmdLetBinding()]
    [OutputType([Whiskey.TaskAttribute])]
    param(
        # Return tasks that are obsolete. Otherwise, no obsolete tasks are returned.
        [switch]$Force
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    [Management.Automation.FunctionInfo]$functionInfo = $null;

    foreach( $functionInfo in (Get-Command -CommandType Function) )
    {
        $functionInfo.ScriptBlock.Attributes | 
            Where-Object { $_ -is [Whiskey.TaskAttribute] } |
            ForEach-Object {
                $_.CommandName = $functionInfo.Name
                $_
            } |
            Where-Object {
                if( $Force )
                {
                    $true
                }
                return -not $_.Obsolete
            }
    }
}