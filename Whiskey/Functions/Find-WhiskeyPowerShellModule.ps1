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

    Write-WhiskeyDebug '\Find-WhiskeyPowerShellModule\' -Indent

    function Import
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Name,

            [Parameter(Mandatory)]
            [Version] $MinimumVersion,

            [Parameter(Mandatory)]
            [Version] $MaximumVersion
        )

        Write-WhiskeyDebug "Importing module $($Name) for version $($MinimumVersion) - $($MaximumVersion)."
        $module = Get-Module -Name $Name
        if( $module )
        {
            if( $module.Version -ge $MinimumVersion -and $module.Version -le $MaximumVersion )
            {
                Write-WhiskeyDebug "Module $($Name) $($module.Version) already imported."
                return
            }

            Write-WhiskeyDebug "Removing module $($Name) $($module.Version)."
            $module | Remove-Module -Force
        }
        
        $importFailed = $true
        try
        {
            Import-Module -Name $Name `
                          -MinimumVersion $MinimumVersion `
                          -MaximumVersion $MaximumVersion `
                          -Global
            Write-WhiskeyDebug "Imported module $($Name) $((Get-Module -Name $Name).Version)."
            $importFailed = $false
        }
        finally
        {
            if( $importFailed )
            {
                Write-WhiskeyDebug "Exception importing $($Name) module: $($Global:Error[0])"

                Write-WhiskeyDebug '\PSModulePath\' -Indent
                $env:PSModulePath -split ([IO.Path]::PathSeparator) | Write-WhiskeyDebug
                Write-WhiskeyDebug '/PSModulePath/' -Outdent

                Write-WhiskeyDebug '\Get-Module\' -Indent
                Get-Module | Out-String | Write-WhiskeyDebug
                Write-WhiskeyDebug '/Get-Module/' -Outdent

                Write-WhiskeyDebug '\Get-Module -ListAvailable\' -Indent
                Get-Module -ListAvailable | Out-String | Write-WhiskeyDebug
                Write-WhiskeyDebug '/Get-Module -ListAvailable/' -Outdent
            }
        }
    }

    try
    {
        Register-WhiskeyPSModulePath -PSModulesRoot $BuildRoot

        # If you want to upgrade the PackageManagement and PowerShellGet versions, you must also update:
        # * Install-WhiskeyRequiredModule
        Import -Name 'PackageManagement' `
               -MinimumVersion $script:pkgMgmtMinVersion `
               -MaximumVersion $script:pkgMgmtMaxVersion
        Import -Name 'PowerShellGet' -MinimumVersion $script:psGetMinVersion -MaximumVersion $script:psGetMaxVersion

        $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Module' -AllowPrerelease:$AllowPrerelease

        Write-WhiskeyDebug -Message ('{0}  {1} ->' -f $Name,$Version)
        if( $Version )
        {
            $atVersionString = ' at version {0}' -f $Version

            if( -not [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($version) -and `
                [Version]::TryParse($Version,[ref]$null) )
            {
                $tempVersion = [Version]$Version
                if( $tempVersion -and ($tempVersion.Build -lt 0) )
                {
                    $Version = [Version]('{0}.{1}.0' -f $tempVersion.Major, $tempVersion.Minor)
                }
            }

            Write-WhiskeyDebug -Message "Searching for module $($Name) $($Version)."
            $module = 
                Find-Module -Name $Name -AllVersions @allowPrereleaseArg |
                Where-Object { $_.Version.ToString() -like $Version } |
                Sort-Object -Property 'Version' -Descending
        }
        else
        {
            Write-WhiskeyDebug -Message "Searching for latest version of module $($Name)."
            $atVersionString = ''
            $module = Find-Module -Name $Name @allowPrereleaseArg -ErrorAction Ignore
        }

        if( -not $module )
        {
            $registeredRepositories = Get-PSRepository | ForEach-Object { ('{0} ({1})' -f $_.Name,$_.SourceLocation) }
            $registeredRepositories = $registeredRepositories -join ('{0} * ' -f [Environment]::NewLine)
            Write-WhiskeyError -Message ('Failed to find PowerShell module {0}{1} in any of the registered PowerShell repositories:{2} {2} * {3} {2}' -f $Name, $atVersionString, [Environment]::NewLine, $registeredRepositories)
            return
        }

        $module = $module | Select-Object -First 1
        Write-WhiskeyDebug ($module | Format-List | Out-String)
        Write-WhiskeyDebug -Message ('{0}  {1}    {2}' -f (' ' * $Name.Length),(' ' * $Version.Length),$module.Version)
        return $module
    }
    finally
    {
        Write-WhiskeyDebug '/Find-WhiskeyPowerShellModule/' -Outdent
    }
}
