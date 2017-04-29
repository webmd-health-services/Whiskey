
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCiTest.ps1' -Resolve)

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

        [Version]
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    $moduleRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Modules'

    if( $LikePowerShell4 )
    {        
        $Name = '{0}.{1}' -f $WithName, $WithVersion
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion 
    }
    $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $Name

    New-Item -Name $WithName -Path $moduleRoot -ItemType 'Directory' | Out-Null
}

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [Version]
        $WithVersion,

        [String]
        $WithName = 'NUnit.Runners',

        [string]
        $Version = '2.6.4'
    )

    $dirName = '{0}.{1}' -f $WithName, $Version
    $installRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
}

function WhenUninstallingPowerShellModule
{
    [CmdletBinding()]
    param(
        [Version]
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    $Global:Error.Clear()
    Uninstall-WhsCITool -ModuleName $WithName -Version $WithVersion -BuildRoot $TestDrive.FullName
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [Version]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'
    )

    $Global:Error.Clear()
    Uninstall-WhsCITool -NuGetPackageName $WithName -Version $WithVersion -BuildRoot $TestDrive.FullName
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

        [version]
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    if( $LikePowerShell4 )
    {        
        $Name = '{0}.{1}' -f $WithName, $WithVersion
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion 
    }

    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'Modules'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    It 'should successfully uninstall the PowerShell Module' {
        $uninstalledPath | Should not Exist
    }

    It 'Should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
}

function ThenNuGetPackageUninstalled
{
    [CmdLetBinding()]
    param(
        [version]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'
    )

    $Name = '{0}.{1}' -f $WithName, $Version
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    It 'should successfully uninstall the NuGet Package' {
        $uninstalledPath | Should not Exist
    }

    It 'Should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
}

Describe 'Uninstall-WhsCITool.when given an NuGet Package' {
    GivenAnInstalledNuGetPackage
    WhenUninstallingNuGetPackage
    ThenNuGetPackageUnInstalled
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module under PowerShell 4' {
    GivenAnInstalledPowerShellModule -LikePowerShell4
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell4
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module under PowerShell 5' {
    GivenAnInstalledPowerShellModule -LikePowerShell5
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell5
}
