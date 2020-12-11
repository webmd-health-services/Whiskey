Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$output = $null

function Init
{
    $Global:Error.Clear()
    Mock -CommandName 'Import-Module' -ModuleName 'Whiskey' -MockWith { $true }
}

function GivenModuleInstalledLocally
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { $true }
}

function GivenModuleNotInstalledLocally
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { $false } 
}

function GivenModuleInstalledGlobally
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

function GivenModuleNotInstalledGlobally
{
    $globalModule = [pscustomobject]@{
        'Found' = $false;
        'Path' = $null;
    }

    Mock -CommandName 'Test-GlobalPowerShellModule' -ModuleName 'Whiskey'  -MockWith { return $globalModule }.GetNewClosure()
}

function WhenImportingPowerShellModule
{
    param(
        [String] $Name,
        [String] $Version,
        [String] $PSModulesRoot,
        [Switch] $InstalledGlobally
    )

    $parameter = @{
        'Name' = $Name;
        'Version' = $Version;
        'PSModulesRoot' = $PSModulesRoot;
        'InstalledGlobally' = $InstalledGlobally;
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenImportsLocalModule
{
    param(
        $ModulePath
    )

    Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModulePath } -Times 1
}

function ThenImportsGlobalModule
{
    param(
        $ModuleName,
        $ModuleVersion,
        $ModulePath
    )
    
    Assert-MockCalled -CommandName 'Test-GlobalPowerShellModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModuleName -and $Version -eq $ModuleVersion} -Times 1
    Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModulePath } -Times 1
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

Describe 'Import-WhiskeyPowerShellModule.when module to import globally is installed globally' {
    AfterEach { Reset }
    it 'should import global module' {
        init
        GivenModuleInstalledGlobally -Path 'Path/To/Global/Zip/Module'
        GivenModuleNotInstalledLocally
        WhenImportingPowerShellModule -Name 'Zip' -Version '0.2.0' -InstalledGlobally
        ThenImportsGlobalModule -ModuleName 'Zip' -ModuleVersion '0.2.0' -ModulePath 'Path/To/Global/Zip/Module'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module to import globally is not installed globally' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        GivenModuleNotInstalledGlobally
        {WhenImportingPowerShellModule -Name 'unknownModule' -InstalledGlobally} | Should -Throw
        ThenErrorMessage -Message 'Module "unknownModule" does not exist in the global scope. Make sure the module is installed and the path to the module is listed in the PSModulePath environment variable.'
    }
}

Describe 'Import-WhiskeyPowerShellModule.when a specific version of a module to import globally is not installed globally' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        GivenModuleNotInstalledGlobally
        {WhenImportingPowerShellModule -Name 'unknownModule' -Version '0.2.0' -InstalledGlobally} | Should -Throw
        ThenErrorMessage -Message 'Version "0.2.0" of module "unknownModule" does not exist in the global scope. Make sure the module is installed and the path to the module is listed in the PSModulePath environment variable.'
    }
}
Describe 'Import-WhiskeyPowerShellModule.when module to import locally is installed locally' {
    AfterEach { Reset }
    it 'should import the latest version of the locally installed module' {
        init
        $testRoot = New-WhiskeyTestRoot
        $modulePath = Join-Path -Path $testRoot -ChildPath 'Zip'
        GivenModuleInstalledLocally
        WhenImportingPowerShellModule -Name 'Zip' -PSModulesRoot $testRoot
        ThenImportsLocalModule -modulePath $modulePath
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when PSModuleRoot is not provided for a module to be imported locally' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        GivenModuleInstalledLocally
        { WhenImportingPowerShellModule -Name 'Zip' } | Should -throw
        ThenErrorMessage -Message 'Module "Zip" does not exist in the local scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.'
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module to import locally is not installed locally' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        $testRoot = New-WhiskeyTestRoot
        GivenModuleNotInstalledLocally
        {WhenImportingPowerShellModule -Name 'unknownModule' -PSModulesRoot $testRoot} | Should -Throw
        ThenErrorMessage -Message 'Module "unknownModule" does not exist in the local scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.'
    }
}
