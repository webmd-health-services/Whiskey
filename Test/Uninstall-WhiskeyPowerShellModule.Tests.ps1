
$PSModuleAutoLoadingPreference = 'None'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null

function GivenAnInstalledPowerShellModule
{
    [CmdLetBinding()]
    param(
        [string]$WithVersion = '0.37.1',

        [string]$WithName = 'SomeModule'
    )

    $moduleRoot = Join-Path -Path $testRoot -ChildPath $PSModulesDirectoryName
    $Name = '{0}\{1}' -f $WithName, $WithVersion
    $importRoot = Join-Path -Path $moduleRoot -ChildPath $WithName
    $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $Name

    if( -not (Test-Path -Path $moduleRoot -PathType Container) )
    {
        New-Item -Path $moduleRoot -ItemType 'Directory' -Force
    }
    New-ModuleManifest -Path (Join-Path -Path $moduleRoot -ChildPath ('{0}.psd1' -f $WithName)) -ModuleVersion $WithVersion | 
        Out-Null

    # Import the module so we can test later that it gets removed before getting deleted.
    Get-Module -Name $WithName | Remove-Module -Force
    Import-Module -Name $importRoot -Force
}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
}

function WhenUninstallingPowerShellModule
{
    [CmdletBinding()]
    param(
        [string]$WithVersion = '0.37.1',

        [string]$WithName = 'SomeModule'
    )

    $Global:Error.Clear()

    $Global:Parameter = @{ 
        'Name' = $WithName;
        'Version' = $WithVersion;
        'BuildRoot' = $testRoot;
    }

    if( $PSBoundParameters.ContainsKey('ErrorAction') )
    {
        $Parameter['ErrorAction'] = $ErrorActionPreference
    }

    Invoke-WhiskeyPrivateCommand -Name 'Uninstall-WhiskeyPowerShellModule' -Parameter $Parameter
}

function ThenPowerShellModuleUninstalled
{
    [CmdLetBinding()]
    param(
        [string]$WithVersion = '0.37.1',

        [string]$WithName = 'SomeModule'
    )

    $Name = '{0}\{1}' -f $WithName, $WithVersion

    $path = Join-Path -Path $testRoot -ChildPath $PSModulesDirectoryName
    $modulePath = Join-Path -Path $path -ChildPath $Name

    Test-Path -Path $modulePath -PathType Container | Should -BeFalse
    $Global:Error | Should -BeNullOrEmpty
    Get-Module -Name $WithName | Should -BeNullOrEmpty
}

function ThenRemovedPSModulesDirectory
{
    Join-Path -Path $testRoot -ChildPath $PSModulesDirectoryName | Should -Not -Exist
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module' {
    It 'should uninstall it' {
        Init
        GivenAnInstalledPowerShellModule 
        WhenUninstallingPowerShellModule
        ThenPowerShellModuleUninstalled 
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module with an empty Version' {
    It 'should uninstall' {
        Init
        GivenAnInstalledPowerShellModule
        WhenUninstallingPowerShellModule -WithVersion ''
        ThenPowerShellModuleUninstalled -WithVersion ''
    }
}

Describe 'Uninstall-WhiskeyPowerShellModule.when given a PowerShell Module with a wildcard Version' {
    It 'should uninstall just versions that match the wildcard' {
        Init
        GivenAnInstalledPowerShellModule -WithVersion '0.37.0'
        GivenAnInstalledPowerShellModule -WithVersion '0.37.1'
        GivenAnInstalledPowerShellModule -WithVersion '0.38.2'
        WhenUninstallingPowerShellModule -WithVersion '0.37.*'
        ThenPowerShellModuleUninstalled -WithVersion '0.37.*'

        $psmodulesRoot = Join-Path -Path $testRoot -ChildPath $PSModulesDirectoryName
        $modulePath = Join-Path -Path $psmodulesRoot -ChildPath 'SomeModule\0.38.2\SomeModule.psd1'
        $modulePath | Should -Exist
    }
}

Describe ('Uninstall-WhiskeyPowerShellModule.when {0} directory is empty after module uninstall' -f $PSModulesDirectoryName) {
    It ('should delete the {0} directory' -f $PSModulesDirectoryName) {
        Init
        GivenAnInstalledPowerShellModule
        WhenUninstallingPowerShellModule
        ThenPowerShellModuleUninstalled
        ThenRemovedPSModulesDirectory
    }
}
