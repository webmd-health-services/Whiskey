
function Get-WhiskeyPSModule
{
    <#
    .SYNOPSIS
    Get's module information, with priority given to modules saved in Whiskey's PSModules directory.

    .DESCRIPTION
    The `Get-WhiskeyPSModule` function return a PowerShell module information object for a module. It returns the same
    object returned by PowerShell's `Get-Module` cmdlet. Pass the name of the module to the `Name` parameter. Pass the
    path to the directory that contains Whiskey's "PSModules" directory (this is usually the build root). The function
    uses `Get-Module` to find the requested module and return its metadata information. The function  validates the
    module's manifest to ensure the module could be imported. Modules that would fail to be imported are not returned.

    If multiple versions of a module exist, the latest version is returned. If you want a specific version, pass the
    version to the `Version` parameter. The `Get-WhiskeyPSModule` will return the latest version that matches
    the version. Wildcards are supported.

    If no modules exist, nothing is returned and no errors are written.

    This function adds the PSModules directory to the `PSModulePath` environment variable. If this path is in the build
    root, it will be removed when a build is done.

    This funcation adds a `ManifestPath` property to the return object that is the path to the module's .psd1 file.

    .LINK
    Find-WhiskeyPSModule

    .EXAMPLE
    Get-WhiskeyPSModule -Name Pester -PSModulesRoot $Context.BuildRoot

    Demonstrates how to call `Get-WhiskeyPSModule` to get module information. In this case, the function will return the
    latest version of the `Pester` module, and will include the PSModules path in the build root.

    .EXAMPLE
    Get-WhiskeyPSModule -Name Pester -PSModulesRoot $Context.BuildRoot -Version '4.*'

    Demonstrates how to call `Get-WhiskeyPSModule` to get module information for a specific version of a module. In this
    example, the function will return the latest 4.x version of the `Pester` module, and will include the PSModules path
    in the build root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Name,

        [String]$Version,

        [Parameter(Mandatory)]
        $PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    Register-WhiskeyPSModulePath -PSModulesRoot $PSModulesRoot
    
    Write-WhiskeyDebug '[Get-WhiskeyPSModules]  PSModulePath:'
    $env:PSModulePath -split [IO.Path]::PathSeparator |
        ForEach-Object { "  $($_)"} |
        Write-WhiskeyDebug
    $modules = Get-Module -Name $Name -ListAvailable -ErrorAction Ignore
    $modules | Out-String | Write-WhiskeyDebug
    $modules |
        Where-Object {
            if( -not $Version )
            {
                return $true
            }

            $moduleInfo = $_

            $moduleVersion = $moduleInfo.Version
            $prerelease = ''
            if( ($moduleInfo | Get-Member 'PreRelease') )
            {
                $prerelease = $moduleInfo.PreRelease
            }
            else
            {
                $privateData = $moduleInfo.PrivateData
                if( $privateData )
                {
                    $psdata = $privateData['PSData']
                    if( $psdata )
                    {
                        $prerelease = $psdata['Prerelease']
                    }
                }
            }

            if( $prerelease )
            {
                $moduleVersion = "$($moduleVersion)-$($prerelease)"
            }

            $msg = "Checking if $($moduleInfo.Name) module's version $($moduleVersion) is like ""$($Version)""."
            Write-WhiskeyDebug -Message $msg
            return $moduleVersion -like $Version
        } |
        Add-Member -Name 'ManifestPath' `
                   -MemberType ScriptProperty `
                   -Value { return Join-Path -Path ($_.Path | Split-Path) -ChildPath "$($_.Name).psd1" } `
                   -Force `
                   -PassThru |
        Where-Object {
            $module = $_

            # Make sure there's a valid module there.
            $numErrorsBefore = $Global:Error.Count
            $manifest = $null
            $debugMsg = "Module $($module.Name) $($module.Version) ($($module.ManifestPath)) has "
            try
            {
                $manifest = Test-ModuleManifest -Path $module.ManifestPath -ErrorAction Ignore -WarningAction Ignore
                Write-WhiskeyDebug -Message ("$($debugMsg)a valid manifest.")
            }
            catch
            {
                Write-WhiskeyDebug -Message ("$($debugMsg)an invalid manifest: $($_).")
                $numErrorsToRemove = $Global:Error.Count - $numErrorsBefore
                for( $idx = 0; $idx -lt $numErrorsToRemove; ++$idx )
                {
                    $Global:Error.RemoveAt(0)
                }
            }

            if( -not $manifest )
            {
                return $false
            }

            return $true
        } |
        # Get the highest versioned module in the order in which they appear in the PSModulePath environment variable.
        Group-Object -Property 'Version' |
        Sort-Object -Property { [Version]$_.Name } -Descending |
        Select-Object -First 1 |
        Select-Object -ExpandProperty 'Group' |
        Select-Object -First 1
}