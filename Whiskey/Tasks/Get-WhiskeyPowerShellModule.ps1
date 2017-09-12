function Get-WhiskeyPowerShellModule 
{
    <#
    .SYNOPSIS
    Short description
    
    .DESCRIPTION
    Long description
    
    .EXAMPLE
    BuildTasks:
    - GetPowerShellModule:
        Name: Carbon
        Version: 2.5.0
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    [Whiskey.Task("GetPowerShellModule",SupportsClean=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $TaskParameter['Name'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "Please Add a Name Property for which PowerShell Module you would like to get."
    }
    $TaskParameter['Path'] = $TaskContext.BuildRoot

    if( -not $TaskParameter['Version'])
    {
        try
        {
            $TaskParameter['Version'] = Resolve-WhiskeyPowerShellModuleVersion -ModuleName $TaskParameter['Name']
        }
        catch
        {
            Write-Error 'Cannot Find Version from PowerShell Module ''{0}''.' -f $TaskParameter['Name']
        }
    }

    if( $TaskContext.ShouldClean() )
    {
        Uninstall-WhiskeyTool -ModuleName $TaskParameter['Name'] -BuildRoot $TaskContext.BuildRoot
        return
    }
    return Install-WhiskeyTool -ModuleName $TaskParameter['Name'] -Version $TaskParameter['Version'] -DownloadRoot $TaskContext.BuildRoot
}