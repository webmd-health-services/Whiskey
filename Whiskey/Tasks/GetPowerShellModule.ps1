function Get-WhiskeyPowerShellModule
{
    [CmdletBinding()]
    [Whiskey.Task('GetPowerShellModule',SupportsClean,SupportsInitialize)]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [String]$Name,

        [String]$Version,

        [switch]$AllowPrerelease,

        [Whiskey.Tasks.ValidatePath(AllowNonexistent)]
        [String]$Path,

        [switch]$Import
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $Name )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Property "Name" is mandatory. It should be set to the name of the PowerShell module you want installed.'
        return
    }

    if( $TaskContext.ShouldClean )
    {
        Uninstall-WhiskeyPowerShellModule -Name $Name -BuildRoot $TaskContext.BuildRoot -Path $Path
        return
    }
    
    $module = Resolve-WhiskeyPowerShellModule -Name $Name `
                                              -Version $Version `
                                              -BuildRoot $TaskContext.BuildRoot `
                                              -AllowPrerelease:$AllowPrerelease `
                                              -Path $Path `
                                              -ErrorAction Stop
    if( -not $module )
    {
        return
    }

    $destination = Join-Path -Path $TaskContext.BuildRoot -ChildPath $powershellModulesDirectoryName
    if( $Path )
    {
        $destination = $Path
    }
    $destination = Resolve-Path -Path $destination -Relative -ErrorAction Ignore
    if( $destination )
    {
        $destination = ' to {0}' -f $destination
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('Installing PowerShell module {0} {1}{2}.' -f $Name,$module.Version,$destination)
    $moduleRoot = Install-WhiskeyPowerShellModule -Name $Name `
                                                  -Version $module.Version `
                                                  -BuildRoot $TaskContext.BuildRoot `
                                                  -SkipImport:(-not $Import) `
                                                  -AllowPrerelease:$AllowPrerelease `
                                                  -Path $Path `
                                                  -ErrorAction Stop
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  {0}' -f $moduleRoot)
}