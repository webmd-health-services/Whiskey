Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$output = $null

function Init
{
    $Global:Error.Clear()
    $script:testRoot = New-WhiskeyTestRoot
}

function GivenModuleInstalledLocally
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { $true }
    Mock -CommandName 'Import-Module' -ModuleName 'Whiskey' -MockWith { $true }
}

function GivenModuleInstalledGlobally
{
    Mock -CommandName 'Test-WhiskeyPowershellModule' -ModuleName 'Whiskey' -MockWith { $true }
    Mock -CommandName 'Import-Module' -ModuleName 'Whiskey' -MockWith { $true }
}

function GivenModuleNotInstalledLocally
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { $false } 
}

function GivenModuleNotInstalledGlobally
{
    Mock -CommandName 'Test-WhiskeyPowershellModule' -ModuleName 'Whiskey' -MockWith { $false }
}

function Import-PowerShellModule
{
    param(
        [String[]]$moduleName
    )

    $parameter = @{
        'Name' = $moduleName;
        'PSModulesRoot' = $testRoot;
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenImportsLocalModule
{
    Assert-MockCalled -CommandName 'Test-Path' -ModuleName 'Whiskey' -Times 1
    Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -Times 1
}

function ThenImportsGlobalModule
{
    Assert-MockCalled -CommandName 'Test-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -Times 1
    Assert-MockCalled -CommandName 'Test-Path' -ModuleName 'Whiskey' -Times 0
    Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -Times 1
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

Describe 'Import-WhiskeyPowerShellModule.when module does not exist' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        {Import-PowerShellModule -moduleName 'unknownModule'} | Should -Throw
        ThenErrorMessage -Message 'Module "unknownModule" does not exist. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.'
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module is installed locally' {
    AfterEach { Reset }
    it 'should import module' {
        init
        GivenModuleInstalledLocally 'Zip'
        GivenModuleNotInstalledGlobally
        Import-PowerShellModule 'Zip'
        ThenImportsLocalModule
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module is installed globally and locally' {
    AfterEach { Reset }
    it 'should import module' {
        init
        GivenModuleInstalledGlobally
        GivenModuleInstalledLocally 'Zip'
        import-PowerShellModule 'Zip'
        ThenImportsGlobalModule
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module is installed globally' {
    AfterEach { Reset }
    it 'should import global module' {
        init
        GivenModuleInstalledGlobally
        GivenModuleNotInstalledLocally
        Import-PowerShellModule 'Zip'
        ThenImportsGlobalModule
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when called with multiple installed modules' {
    AfterEach { Reset }
    it 'should import all module' {
        init
        $modules = @('Zip', 'BuildMasterAutomation', 'ProGetAutomation')
        GivenModuleInstalledGlobally
        Import-PowerShellModule -moduleName $modules
        Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -Times 3
        ThenNoErrors
    }
}