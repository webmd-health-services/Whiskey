

function Get-WhiskeyTasks
{
    <#
    .SYNOPSIS

    .DESCRIPTION
    
    .EXAMPLE
    
    #>
    [CmdLetBinding()]
    param()

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $knownTasks = @{ }
    [Management.Automation.FunctionInfo]$item = $null;
    
    foreach( $item in (Get-Command -CommandType Function) )
    {
        $attr = $item.ScriptBlock.Attributes | Where-Object { $_ -is [Whiskey.TaskAttribute] }
        if( -not $attr )
        {
            continue
        }
        $knownTasks[$attr.Name] = $item.Name
    }
    
    return $knownTasks
}