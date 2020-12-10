Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$output = $null
$globalModules = @()

function Init
{
    $script:globalModules = @()
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
        [String]$Name,
        [String]$Version,
        [String]$Path
    )

    $script:globalModules += [pscustomobject]@{
        'Name' = $Name;
        'Version' = $Version;
        'Path' = $Path;
    }
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

    $globalModules = $script:globalModules
    Mock -CommandName 'Get-Module' -ModuleName 'Whiskey' -MockWith { $globalModules }.GetNewClosure()

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
        $ModulePath
    )
    Assert-MockCalled -CommandName 'Get-Module' -ModuleName 'Whiskey' -Exactly 1 -ParameterFilter { 
        $Name -eq $ModuleName -and`
        $ListAvailable -eq $true -and`
        $ErrorAction -eq $Ignore
    }
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
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.2.0' -Path 'Path/To/Global/Zip/Module'
        GivenModuleNotInstalledLocally
        WhenImportingPowerShellModule -Name 'Zip' -Version '0.2.0' -InstalledGlobally
        ThenImportsGlobalModule -ModuleName 'Zip' -ModulePath 'Path/To/Global/Zip/Module'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module to import globally is installed globally and version number is not given' {
    AfterEach { Reset }
    it 'should import the latest version of global module' {
        init
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.2.0' -Path 'Path/To/Latest/Global/Zip/Module'
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.1.0' -Path 'Path/To/Previous/Global/Zip/Module'
        GivenModuleNotInstalledLocally
        WhenImportingPowerShellModule -Name 'Zip' -InstalledGlobally
        ThenImportsGlobalModule -ModuleName 'Zip' -ModulePath 'Path/To/Latest/Global/Zip/Module'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module is installed globally and version number contains a wildcard' {
    AfterEach { Reset }
    it 'should import the latest version of global module matching the wildcard' {
        init
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.2.0' -Path 'Path/To/Latest/Global/Zip/Module'
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.1.0' -Path 'Path/To/Previous/Global/Zip/Module'
        GivenModuleNotInstalledLocally
        WhenImportingPowerShellModule -Name 'Zip' -Version '0.*' -InstalledGlobally
        ThenImportsGlobalModule -ModuleName 'Zip' -ModulePath 'Path/To/Latest/Global/Zip/Module'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module to import globally is installed globally with a different version' {
    AfterEach { Reset }
    it 'should not import global module' {
        init
        GivenModuleInstalledGlobally -Name 'Zip' -Version '0.2.0' -Path 'Path/To/Global/Zip/Module'
        GivenModuleNotInstalledLocally
        { WhenImportingPowerShellModule -Name 'Zip' -Version '0.3.0' -InstalledGlobally } | Should -throw
        ThenErrorMessage -Message 'Version "0.3.0" of module "Zip" does not exist in the global scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.'
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module to import globally is not installed globally' {
    AfterEach { Reset }
    it 'should throw an error' {
        init
        {WhenImportingPowerShellModule -Name 'unknownModule' -InstalledGlobally} | Should -Throw
        ThenErrorMessage -Message 'Module "unknownModule" does not exist in the global scope. Make sure your task uses the "RequiresTool" attribute so that the module gets installed automatically.'
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
    it 'should not import module' {
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
