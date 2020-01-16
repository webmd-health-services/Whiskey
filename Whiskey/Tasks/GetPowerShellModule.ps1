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

        [Whiskey.Tasks.ValidatePath(AllowNonexistent,Create,PathType='Directory')]
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

    if( -not $Path )
    {
        $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath $powershellModulesDirectoryName
        if( -not (Test-Path -Path $Path -PathType Container) )
        {
            New-Item -Path $Path -ItemType 'Directory' | Out-Null
        }
        $Path = $Path | Resolve-Path -Relative
    }

    # PackageManagement/PowerShellGet functions don't like relative paths.
    $fullPath = $Path | Resolve-Path | Select-Object -ExpandProperty 'ProviderPath'

    $module = Resolve-WhiskeyPowerShellModule -Name $Name `
                                              -Version $Version `
                                              -BuildRoot $TaskContext.BuildRoot `
                                              -AllowPrerelease:$AllowPrerelease `
                                              -ErrorAction Stop
    if( -not $module )
    {
        return
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('Installing PowerShell module {0} {1} to {2}.' -f $Name,$module.Version,$Path)
    $moduleRoot = Install-WhiskeyPowerShellModule -Name $Name `
                                                  -Version $module.Version `
                                                  -BuildRoot $TaskContext.BuildRoot `
                                                  -SkipImport:(-not $Import) `
                                                  -AllowPrerelease:$AllowPrerelease `
                                                  -Path $fullPath `
                                                  -ErrorAction Stop
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  {0}' -f $moduleRoot)
}