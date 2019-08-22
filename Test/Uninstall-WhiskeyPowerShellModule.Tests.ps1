
$powerShellModulesDirectoryName = 'PSModules'
$PSModuleAutoLoadingPreference = 'None'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Import-WhiskeyPowerShellModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Uninstall-WhiskeyPowerShellModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyPowerShellModule.ps1' -Resolve)

function GivenAnInstalledPowerShellModule
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4,

        [String]
        $WithVersion = '0.37.1',

        [String]
        $WithName = 'Whiskey'
    )

    $moduleRoot = Join-Path -Path $TestDrive.FullName -ChildPath $powerShellModulesDirectoryName
    if( $LikePowerShell4 )
    {
        $Name = '{0}' -f $WithName
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion
    }
    $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $Name

    New-Item -Name ('{0}.psd1' -f $WithName) -Path $moduleRoot -ItemType File -Force | Out-Null
}

function WhenUninstallingPowerShellModule
{
    [CmdletBinding()]
    param(
        [String]
        $WithVersion = '0.37.1',

        [String]
        $WithName = 'Whiskey'
    )

    $Global:Error.Clear()
    Push-Location $TestDrive.FullName
    try
    {
        Uninstall-WhiskeyPowerShellModule -Name $WithName -Version $WithVersion
    }
    finally
    {
        Pop-Location
    }
}

function ThenPowerShellModuleUninstalled
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4,

        [String]
        $WithVersion = '0.37.1',

        [String]
        $WithName = 'Whiskey'
    )

    if( $LikePowerShell4 )
    {
        $Name = '{0}' -f $WithName
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion
    }

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $powerShellModulesDirectoryName
    $modulePath = Join-Path -Path $path -ChildPath $Name

    Test-Path -Path $modulePath -PathType Container | Should -BeFalse
    $Global:Error | Should -BeNullOrEmpty
}

function ThenRemovedPSModulesDirectory
{
    Join-Path -Path $TestDrive.FullName -ChildPath $powerShellModulesDirectoryName | Should -Not -Exist
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 4' {
    It 'should uninstall it' {
        GivenAnInstalledPowerShellModule -LikePowerShell4
        WhenUninstallingPowerShellModule
        ThenPowerShellModuleUninstalled -LikePowerShell4
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5' {
    It 'should uninstall it' {
        GivenAnInstalledPowerShellModule -LikePowerShell5
        WhenUninstallingPowerShellModule
        ThenPowerShellModuleUninstalled -LikePowerShell5
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5 with an empty Version' {
    It 'should uninstall' {
        GivenAnInstalledPowerShellModule -LikePowerShell5
        WhenUninstallingPowerShellModule -WithVersion ''
        ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion ''
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5 with a wildcard Version' {
    It 'should uninstall just versions that match the wildcard' {
        GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion '0.37.0'
        GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion '0.37.1'
        GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion '0.38.2'
        WhenUninstallingPowerShellModule -WithVersion '0.37.*'
        ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion '0.37.*'

        $psmodulesRoot = Join-Path -Path $TestDrive.FullName -ChildPath $powerShellModulesDirectoryName
        $modulePath = Join-Path -Path $psmodulesRoot -ChildPath 'Whiskey\0.38.2\Whiskey.psd1'
        $modulePath | Should -Exist
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when PSModules directory is empty after module uninstall' {
    It 'should delete the PSModules directory' {
        GivenAnInstalledPowerShellModule -LikePowerShell5
        WhenUninstallingPowerShellModule
        ThenPowerShellModuleUninstalled -LikePowerShell5
        ThenRemovedPSModulesDirectory
    }
}
