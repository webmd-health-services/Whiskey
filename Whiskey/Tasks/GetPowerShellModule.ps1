function Get-WhiskeyPowerShellModule
{
    [CmdletBinding()]
    [Whiskey.Task('GetPowerShellModule',SupportsClean,SupportsInitialize)]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $TaskParameter['Name'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property "Name" is mandatory. It should be set to the name of the PowerShell module you want installed.'
        return
    }

    if( $TaskContext.ShouldClean )
    {
        Uninstall-WhiskeyPowerShellModule -Name $TaskParameter['Name'] -BuildRoot $TaskContext.BuildRoot
        return
    }

    $module = Resolve-WhiskeyPowerShellModule -Name $TaskParameter['Name'] `
                                              -Version $TaskParameter['Version'] `
                                              -BuildRoot $TaskContext.BuildRoot `
                                              -ErrorAction Stop
    if( -not $module )
    {
        return
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('Installing PowerShell module {0} {1}.' -f $TaskParameter['Name'],$module.Version)
    $moduleRoot = Install-WhiskeyPowerShellModule -Name $TaskParameter['Name'] `
                                                  -Version $module.Version `
                                                  -BuildRoot $TaskContext.BuildRoot `
                                                  -SkipImport `
                                                  -ErrorAction Stop
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  {0}' -f $moduleRoot)
}