
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
    $WithVersion = Resolve-WhiskeyPowerShellModule -Name $WithName -Version $WithVersion | Select-Object -ExpandProperty 'Version'
    if( $LikePowerShell4 )
    {
        $Name = '{0}' -f $WithName
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion
    }
    $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $Name

    New-Item -Name $WithName -Path $moduleRoot -ItemType 'Directory' | Out-Null
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

    $WithVersion = Resolve-WhiskeyPowerShellModule -Name $WithName -Version $WithVersion | Select-Object -ExpandProperty 'Version'
    if( $LikePowerShell4 )
    {
        $Name = '{0}' -f $WithName
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion
    }

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $powerShellModulesDirectoryName
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    It 'should successfully uninstall the PowerShell Module' {
        $uninstalledPath | Should -Not -Exist
    }

    It 'Should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 4' {
    GivenAnInstalledPowerShellModule -LikePowerShell4
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell4
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5' {
    GivenAnInstalledPowerShellModule -LikePowerShell5
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell5
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5 with an empty Version' {
    GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion ''
    WhenUninstallingPowerShellModule -WithVersion ''
    ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion ''
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module under PowerShell 5 with a wildcard Version' {
    GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion '0.37.*'
    WhenUninstallingPowerShellModule -WithVersion '4.*'
    ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion '0.37.*'
}
