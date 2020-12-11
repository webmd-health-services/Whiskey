Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# If you want to upgrade the PackageManagement and PowerShellGet versions, you must also update:
# * Whiskey\Functions\Resolve-WhiskeyPowerShellModule.ps1
# * Whiskey\Tasks\PublishPowerShellModule.ps1
# * whiskey.yml
$packageManagementVersion = '1.4.5'
$powerShellGetVersion = '2.2.1'

$moduleName = $null
$moduleVersion = $null
$output = $null
$testRoot = $null

function Init
{
    $Global:Error.Clear()
    $script:moduleName = $null
    $script:moduleVersion = $null
    $script:output = $null
    $script:testRoot = New-WhiskeyTestRoot
    Mock -CommandName 'Import-WhiskeyPowershellModule' -ModuleName 'Whiskey'
}

function GivenName
{
    param(
        $Name
    )
    $script:moduleName = $Name
}

function GivenVersion
{
    param(
        $Version
    )
    $script:moduleVersion = $Version
}

function GivenReturnedModuleFromTwoRepositories
{
    $pesterRepo1 = Find-Module -Name 'Pester' | Select-Object -First 1
    $pesterRepo2 = $pesterRepo1.PSObject.Copy()
    $pesterRepo2.Repository = 'Another PowerShellGet Repository'

    $moduleOutput = @($pesterRepo1, $pesterRepo2)

    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey' -MockWith { $moduleOutput }.GetNewClosure()
}

function GivenModuleDoesNotExist
{
    $script:moduleName = 'nonexistentmodule'
    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey'
}

function GivenPkgMgmtModulesInstalledGlobally
{
    param(
        [String]$Path
    )

    $globalModule = [pscustomobject]@{
        'Found' = $true;
        'Path' = $Path;
    }

    Mock -CommandName 'Test-GlobalPowerShellModule' -ModuleName 'Whiskey'  -MockWith { return $globalModule }.GetNewClosure()
}

function GivenPkgMgmtModulesNotInstalledGlobally
{
    $globalModule = [pscustomobject]@{
        'Found' = $false;
        'Path' = $null;
    }

    Mock -CommandName 'Test-GlobalPowerShellModule' -ModuleName 'Whiskey'  -MockWith { return $globalModule }.GetNewClosure()
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function WhenResolvingPowerShellModule
{
    [CmdletBinding()]
    param(
        [switch]$SkipCaching
    )

    $parameter = @{
        'Name' = $moduleName;
        'BuildRoot' = $testRoot;
    }

    if( $moduleVersion )
    {
        $parameter['Version'] = $moduleVersion
    }

    if( -not $SkipCaching )
    {
        # Put the PackageManagement and PowerShellGet modules in place so they don't get installed and make the tests take a long time.
        Initialize-WhiskeyTestPSModule -BuildRoot $testRoot
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

function ThenGlobalPkgManagmentModulesImported
{
        $modulesRoot = Join-Path -Path $testRoot -ChildPath $TestPSModulesDirectoryName
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 0 -ParameterFilter { 
            $Name -eq 'PackageManagement' -and`
            $PSModulesRoot -eq $modulesRoot
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 0 -ParameterFilter { 
            $Name -eq 'PowerShellGet' -and`
            $PSModulesRoot -eq $modulesRoot
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { 
            $Name -eq 'PackageManagement' -and`
            $Version -eq $packageManagementVersion -and`
            $InstalledGlobally -eq $true
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { 
            $Name -eq 'PowerShellGet' -and`
            $Version -eq $powerShellGetVersion -and`
            $InstalledGlobally -eq $true
        }

}

function ThenLocalPkgManagementModulesImported
{
        $modulesRoot = Join-Path -Path $testRoot -ChildPath $TestPSModulesDirectoryName
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { 
            $Name -eq 'PackageManagement' -and`
            $PSModulesRoot -eq $modulesRoot
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { 
            $Name -eq 'PowerShellGet' -and`
            $PSModulesRoot -eq $modulesRoot
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 0 -ParameterFilter { 
            $Name -eq 'PackageManagement' -and`
            $Version -eq $packageManagementVersion -and`
            $InstalledGlobally -eq $true
        }
        Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 0 -ParameterFilter { 
            $Name -eq 'PowerShellGet' -and`
            $Version -eq $powerShellGetVersion -and`
            $InstalledGlobally -eq $true
        }
}

function ThenReturnedModuleInfoObject
{
    $count = $output | Measure-Object | Select-Object -ExpandProperty 'Count'
    $count | Should -Be 1
    $output | Get-Member -Name 'Version' | Should -Not -BeNullOrEmpty
    $output | Get-Member -Name 'Repository' | Should -Not -BeNullOrEmpty
}

function ThenReturnedModule
{
    param(
        $Name,
        $AtVersion
    )

    $output.Name | Should -Be $Name

    if ($AtVersion)
    {
        $output.Version.ToString() | Should -BeLike $AtVersion
    }
}

function ThenReturnedNothing
{
    $output | Should -BeNullOrEmpty
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenErrorMessage
{
    param(
        $Message
    )

    $Global:Error | Should -Match $Message 
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name "Pester"' {
    AfterEach { Reset }
    It 'should find it' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalledGlobally
        WhenResolvingPowerShellModule
        ThenLocalPkgManagementModulesImported
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name "Pester" and Version "4.3.1"' {
    AfterEach { Reset }
    It 'should resolve that version' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.1'
        GivenPkgMgmtModulesNotInstalledGlobally
        WhenResolvingPowerShellModule
        ThenLocalPkgManagementModulesImported
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given Version wildcard' {
    AfterEach { Reset }
    It 'should resolve the latest version that matches the wildcard' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.*'
        GivenPkgMgmtModulesNotInstalledGlobally
        WhenResolvingPowerShellModule
        ThenLocalPkgManagementModulesImported
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module that does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModuleDoesNotExist
        GivenPkgMgmtModulesNotInstalledGlobally
        WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to find'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when Find-Module returns module from two repositories' {
    AfterEach { Reset }
    It 'should pick one' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalledGlobally
        GivenReturnedModuleFromTwoRepositories
        WhenResolvingPowerShellModule
        ThenLocalPkgManagementModulesImported
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when package management modules aren''t installed' {
    AfterEach { Reset }
    It 'should install package management modules' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalledGlobally
        WhenResolvingPowerShellModule -SkipCaching
        Join-Path -Path $testRoot -ChildPath ('{0}\PackageManagement\{1}' -f $TestPSModulesDirectoryName,$packageManagementVersion) | Should -Exist
        Join-Path -Path $testRoot -ChildPath ('{0}\PowerShellGet\{1}' -f $TestPSModulesDirectoryName,$powerShellGetVersion) | Should -Exist
        ThenLocalPkgManagementModulesImported
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when package management modules manifest is missing' {
    AfterEach { Reset }
    It 'should uninstall potentially corrupt modules' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalledGlobally
        $manifestPath = Join-Path -Path $testRoot -ChildPath ('{0}\PackageManagement\{1}\PackageManagement.psd1' -f $TestPSModulesDirectoryName,$packageManagementVersion) 
        New-Item -Path $manifestPath -ItemType 'Directory' -Force
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Ignore } | Should -Throw
        $Global:Error.Clear()
        WhenResolvingPowerShellModule -SkipCaching
        Test-ModuleManifest -Path $manifestPath | Should -Not -BeNullOrEmpty
        ThenLocalPkgManagementModulesImported
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when package management modules manifests can''t be loaded' {
    AfterEach { Reset }
    It 'should uninstall potentially corrupt modules' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalledGlobally
        $manifestPath = Join-Path -Path $testRoot -ChildPath ('{0}\PackageManagement\{1}\PackageManagement.psd1' -f $TestPSModulesDirectoryName,$packageManagementVersion) 
        New-Item -Path $manifestPath -ItemType 'File' -Force
        '@{ "RequiredAssemblies" = "Fubar.dll" }' | Set-Content -Path $manifestPath
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Ignore } | Should -Throw
        $Global:Error.Clear()
        WhenResolvingPowerShellModule -SkipCaching
        Test-ModuleManifest -Path $manifestPath | Should -Not -BeNullOrEmpty
        ThenLocalPkgManagementModulesImported
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when package management modules are installed globally' {
    AfterEach { Reset }
    It 'should not install package management modules' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesInstalledGlobally
        WhenResolvingPowerShellModule -SkipCaching
        Join-Path -Path $testRoot -ChildPath ('{0}\PackageManagement\{1}' -f $TestPSModulesDirectoryName,$packageManagementVersion) | Should -Not -Exist
        Join-Path -Path $testRoot -ChildPath ('{0}\PowerShellGet\{1}' -f $TestPSModulesDirectoryName,$powerShellGetVersion) | Should -Not -Exist
        ThenGlobalPkgManagmentModulesImported
        ThenNoErrors
    }
}
