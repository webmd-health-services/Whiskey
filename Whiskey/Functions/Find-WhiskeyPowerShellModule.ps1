function Find-WhiskeyPowerShellModule
{
    <#
    .SYNOPSIS
    Searches for a PowerShell module using PowerShellGet to ensure it exists and returns the resulting object from PowerShellGet.

    .DESCRIPTION
    The `Find-WhiskeyPowerShellModule` function takes a `Name` of a PowerShell module and uses PowerShellGet's `Find-Module` cmdlet to search for the module. If the module is found, the object from `Find-Module` describing the module is returned. If no module is found, an error is written and nothing is returned. If the module is found in multiple PowerShellGet repositories, only the first one from `Find-Module` is returned.

    If a `Version` is specified then this function will search for that version of the module from all versions returned from `Find-Module`. If the version cannot be found, an error is written and nothing is returned.

    `Version` supports wildcard patterns.

    .EXAMPLE
    Find-WhiskeyPowerShellModule -Name 'Pester'

    Demonstrates getting the module info on the latest version of the Pester module.

    .EXAMPLE
    Find-WhiskeyPowerShellModule -Name 'Pester' -Version '4.*'

    Demonstrates getting the module info on the latest '4.X' version of the Pester module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The name of the PowerShell module.
        [String]$Name,

        # The version of the PowerShell module to search for. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        [String]$Version,

        [Parameter(Mandatory)]
        # The path to the directory where the PSModules directory should be created.
        [String]$BuildRoot,

        # Allow prerelease versions.
        [switch]$AllowPrerelease
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    # If you want to upgrade the PackageManagement and PowerShellGet versions, you must also update:
    # * Test\Find-WhiskeyPowerShellModule.Tests.ps1
    # * Whiskey\Tasks\PublishPowerShellModule.ps1
    # * whiskey.yml
    $packageManagementPackages = @{
        'PackageManagement' = '1.4.7';
        'PowerShellGet' = '2.2.5'
    }
    $modulesToInstall = New-Object 'Collections.ArrayList'
    foreach( $packageName in $packageManagementPackages.Keys )
    {
        $packageVersion = $packageManagementPackages[$packageName]

        # Don't install modules if it's already installed.
        $module = Get-WhiskeyPSModule -Name $packageName -Version $packageVersion -PSModulesRoot $BuildRoot
        if( $module )
        {
            continue
        }

        $moduleInfo = [pscustomobject]@{ 'Name' = $packageName; 'Version' = $packageVersion; }
        $msg = "Module ""$($moduleInfo.Name)"" version $($moduleInfo.Version) is not installed."
        Write-WhiskeyDebug -Message $msg
        [Void]$modulesToInstall.Add($moduleInfo)
    }

    if( $modulesToInstall.Count )
    {
        $modulesRoot = Get-WhiskeyPSModulePath -PSModulesRoot $BuildRoot -Create
        Write-WhiskeyDebug -Message ('Installing package management modules to {0}.  BEGIN' -f $modulesRoot)
        # Install Package Management modules in the background so we can load the new versions. These modules use 
        # assemblies so once you load an old version, you have to re-launch your process to load a newer version.
        Start-Job -ScriptBlock {
            $ErrorActionPreference = $using:ErrorActionPreference
            $VerbosePreference = $using:VerbosePreference
            $InformationPreference = $using:InformationPreference
            $DebugPreference = $using:DebugPreference
            $ProgressPreference = $using:ProgressPreference

            $modulesToInstall = $using:modulesToInstall
            $modulesRoot = $using:modulesRoot

            Get-PackageProvider -Name 'NuGet' -ForceBootstrap | Out-Null
            foreach( $moduleInfo in $modulesToInstall )
            {
                $module = 
                    Find-Module -Name $moduleInfo.Name -RequiredVersion $moduleInfo.Version |
                    Select-Object -First 1
                if( -not $module )
                {
                    continue
                }

                Write-Verbose -Message ('Saving PowerShell module {0} {1} to "{2}" from repository {3}.' -f $module.Name,$module.Version,$modulesRoot,$module.Repository)
                Save-Module -Name $module.Name -RequiredVersion $module.Version -Repository $module.Repository -Path $modulesRoot
            }
        } | Receive-Job -Wait -AutoRemoveJob -InformationAction SilentlyContinue | Out-Null
        Write-WhiskeyDebug -Message ('                                               END')
    }

    foreach( $moduleName in $packageManagementPackages.Keys )
    {
        Import-WhiskeyPowerShellModule -Name $moduleName `
                                       -Version $packageManagementPackages[$moduleName] `
                                       -PSModulesRoot $BuildRoot
    }

    Write-WhiskeyDebug -Message ('{0}  {1} ->' -f $Name,$Version)
    if( $Version )
    {
        $atVersionString = ' at version {0}' -f $Version

        if( -not [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($version) -and [Version]::TryParse($Version,[ref]$null) )
        {
            $tempVersion = [Version]$Version
            if( $TempVersion -and ($TempVersion.Build -lt 0) )
            {
                $Version = [Version]('{0}.{1}.0' -f $TempVersion.Major, $TempVersion.Minor)
            }
        }

        $module = 
            Find-Module -Name $Name -AllVersions -AllowPrerelease:$AllowPrerelease |
            Where-Object { $_.Version.ToString() -like $Version } |
            Sort-Object -Property 'Version' -Descending
    }
    else
    {
        $atVersionString = ''
        $module = Find-Module -Name $Name -AllowPrerelease:$AllowPrerelease -ErrorAction Ignore
    }

    if( -not $module )
    {
        $registeredRepositories = Get-PSRepository | ForEach-Object { ('{0} ({1})' -f $_.Name,$_.SourceLocation) }
        $registeredRepositories = $registeredRepositories -join ('{0} * ' -f [Environment]::NewLine)
        Write-WhiskeyError -Message ('Failed to find PowerShell module {0}{1} in any of the registered PowerShell repositories:{2} {2} * {3} {2}' -f $Name, $atVersionString, [Environment]::NewLine, $registeredRepositories)
        return
    }

    $module = $module | Select-Object -First 1
    Write-WhiskeyDebug -Message ('{0}  {1}    {2}' -f (' ' * $Name.Length),(' ' * $Version.Length),$module.Version)
    return $module
}
