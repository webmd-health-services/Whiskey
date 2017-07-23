
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    $moduleRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Modules'
    $WithVersion = Resolve-WhiskeyPowerShellModuleVersion -ModuleName $WithName -Version $WithVersion
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

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'

    )
    $WithVersion = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $WithName -Version $WithVersion
    if( -not $WithVersion )
    {
        return
    }
    $dirName = '{0}.{1}' -f $WithName, $WithVersion
    $installRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
}

function WhenUninstallingPowerShellModule
{
    [CmdletBinding()]
    param(
        [String]
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    $Global:Error.Clear()
    Uninstall-WhiskeyTool -ModuleName $WithName -Version $WithVersion -BuildRoot $TestDrive.FullName
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'
    )

    $Global:Error.Clear()
    Uninstall-WhiskeyTool -NuGetPackageName $WithName -Version $WithVersion -BuildRoot $TestDrive.FullName
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
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester'
    )

    $WithVersion = Resolve-WhiskeyPowerShellModuleVersion -ModuleName $WithName -Version $WithVersion
    if( $LikePowerShell4 )
    {        
        $Name = '{0}' -f $WithName
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
        [String]
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

function ThenNuGetPackageNotUninstalled
{
        [CmdLetBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners',

        [switch]
        $PackageShouldExist,

        [string]
        $WithError
    )

    $Name = '{0}.{1}' -f $WithName, $Version
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    if( -not $PackageShouldExist )
    {
        It 'should never have installed the package' {
            $uninstalledPath | Should not Exist
        }
    }
    else
    {
        It 'should not have uninstalled the existing package' {
            $uninstalledPath | Should Exist
        }
        Remove-Item -Path $uninstalledPath -Recurse -Force
    }

    It 'Should write errors' {
        $Global:Error | Should Match $WithError
    }
}

Describe 'Uninstall-WhiskeyTool.when given an NuGet Package' {
    GivenAnInstalledNuGetPackage
    WhenUninstallingNuGetPackage
    ThenNuGetPackageUnInstalled
}

Describe 'Uninstall-WhiskeyTool.when given a PowerShell Module under PowerShell 4' {
    GivenAnInstalledPowerShellModule -LikePowerShell4
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell4
}

Describe 'Uninstall-WhiskeyTool.when given a PowerShell Module under PowerShell 5' {
    GivenAnInstalledPowerShellModule -LikePowerShell5
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell5
}

Describe 'Uninstall-WhiskeyTool.when given an NuGet Package with an empty Version' {
    GivenAnInstalledNuGetPackage -WithVersion ''
    WhenUninstallingNuGetPackage -WithVersion ''
    ThenNuGetPackageUnInstalled -WithVersion ''
}

Describe 'Uninstall-WhiskeyTool.when given an NuGet Package with a wildcard Version' {
    GivenAnInstalledNuGetPackage -WithVersion '2.*' -ErrorAction SilentlyContinue
    WhenUninstallingNuGetPackage -WithVersion '2.*' -ErrorAction SilentlyContinue
    ThenNuGetPackageNotUnInstalled -WithVersion '2.*' -WithError 'Wildcards are not allowed for NuGet packages'
}

Describe 'Uninstall-WhiskeyTool.when given a PowerShell Module under PowerShell 5 witn an empty Version' {
    GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion ''
    WhenUninstallingPowerShellModule -WithVersion ''
    ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion ''
}

Describe 'Uninstall-WhiskeyTool.when given a PowerShell Module under PowerShell 5 witn a wildcard Version' {
    GivenAnInstalledPowerShellModule -LikePowerShell5 -WithVersion '4.*'
    WhenUninstallingPowerShellModule -WithVersion '4.*'
    ThenPowerShellModuleUninstalled -LikePowerShell5 -WithVersion '4.*'
}
