Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$globalModules = @()
$output = $null

function Init
{
    $script:globalModules = @()
    $script:output = $null
}

function GivenModuleInstalled
{
    param(
        [Parameter(Mandatory)]
        [String]$Name,

        [Parameter(Mandatory)]
        [String]$AtVersion
    )

    $script:globalModules += [pscustomobject]@{
        'Name' = $Name;
        'Version' = $AtVersion;
    }

    $script:globalModules | Should -Not -BeNullOrEmpty
}


function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenReturnedFalse
{
    $output | Should -Be $false
}

function ThenReturnedTrue
{
    $output | Should -Be $true
}

function WhenTestingPowerShellModule
{
    param(
        [Parameter(Mandatory)]
        [String]$ModuleName,

        [String]$ModuleVersion
    )

    $parameter = @{
        'Name' = $ModuleName;
    }

    if( $ModuleVersion )
    {
        $parameter['Version'] = $ModuleVersion
    }

    if($script:globalModules)
    {
        $globalModules = $script:globalModules
        $globalModules | Should -Not -BeNullOrEmpty
        Mock -CommandName 'Get-Module' -ModuleName 'Whiskey' -MockWith { $globalModules }.GetNewClosure()
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Test-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a non-globally installed module' {
    AfterEach { Reset }
    It 'should return false' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule'
        ThenReturnedFalse
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and wild card version number of a non-globally installed module' {
    AfterEach { Reset }
    It 'should return false' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.*'
        ThenReturnedFalse
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a non-globally installed module' {
    AfterEach { Reset }
    It 'should return false' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.3'
        ThenReturnedFalse
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a globally installed module' {
    AfterEach { Reset }
    It 'should return true' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3'
        WhenTestingPowerShellModule -ModuleName 'TestModule'
        ThenReturnedTrue
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and wild card version number of a globally installed module' {
    AfterEach { Reset }
    It 'should return true' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.*'
        ThenReturnedTrue
    }
}
Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a globally installed module' {
    AfterEach { Reset }
    It 'should return true' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.3'
        ThenReturnedTrue
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a module with multiple installed versions' {
    AfterEach { Reset }
    It 'should return true' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3'
        GivenModuleInstalled -Name 'TestModule' -AtVersion '2.3.1'
        GivenModuleInstalled -Name 'TestModule' -AtVersion '3.2.1'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '2.3.1'
        ThenReturnedTrue
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a globally installed module but a version that is not installed' {
    AfterEach { Reset }
    It 'should return false' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '2.3.1'
        ThenReturnedFalse
    }
}