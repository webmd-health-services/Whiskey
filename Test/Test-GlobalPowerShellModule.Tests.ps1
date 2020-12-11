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
        [String]$AtVersion,

        [Parameter(Mandatory)]
        [String]$Path
    )

    $script:globalModules += [pscustomobject]@{
        'Name' = $Name;
        'Version' = $AtVersion;
        'Path' = $Path;
    }
}


function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenReturnedNoFoundPath
{
    $output.Found | Should -BeFalse
    $output.Path | Should -BeNullOrEmpty
}

function ThenReturnedFoundPath
{
    param(
        [String]$Path
    )

    $output.Found | Should -BeTrue
    $output.Path | Should -Be $Path
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

    $globalModules = $script:globalModules
    Mock -CommandName 'Get-Module' -ModuleName 'Whiskey' -MockWith { $globalModules }.GetNewClosure()

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Test-GlobalPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a non-globally installed module' {
    AfterEach { Reset }
    It 'should not return a module path' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule'
        ThenReturnedNoFoundPath
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and wild card version number of a non-globally installed module' {
    AfterEach { Reset }
    It 'should not return a module path' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.*'
        ThenReturnedNoFoundPath
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a non-globally installed module' {
    AfterEach { Reset }
    It 'should not return a module path' {
        Init
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.3'
        ThenReturnedNoFoundPath
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a globally installed module' {
    AfterEach { Reset }
    It 'should return global module path' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3' -Path 'Path/To/Global/Module'
        WhenTestingPowerShellModule -ModuleName 'TestModule'
        ThenReturnedFoundPath -Path 'Path/To/Global/Module'
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and wild card version number of a globally installed module' {
    AfterEach { Reset }
    It 'should return global module path' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3' -Path 'Path/To/Global/Module'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.*'
        ThenReturnedFoundPath -Path 'Path/To/Global/Module'
    }
}
Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a globally installed module' {
    AfterEach { Reset }
    It 'should return global module path' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3' -Path 'Path/To/Global/Module'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '1.2.3'
        ThenReturnedFoundPath -Path 'Path/To/Global/Module'
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name and a full version number of a module with multiple installed versions' {
    AfterEach { Reset }
    It 'should return path to the requested global module version' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3' -Path 'Path/To/Oldest/Module/Version'
        GivenModuleInstalled -Name 'TestModule' -AtVersion '2.3.1' -Path 'Path/To/Requested/Module/Version'
        GivenModuleInstalled -Name 'TestModule' -AtVersion '3.2.1' -Path 'Path/To/Latest/Module/Version'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '2.3.1'
        ThenReturnedFoundPath -Path 'Path/To/Requested/Module/Version'
    }
}

Describe 'Test-WhiskeyPowerShellModule.when given the name of a globally installed module but a version that is not installed' {
    AfterEach { Reset }
    It 'should not return a module path' {
        Init
        GivenModuleInstalled -Name 'TestModule' -AtVersion '1.2.3' -Path 'Path/To/Global/Module'
        WhenTestingPowerShellModule -ModuleName 'TestModule' -ModuleVersion '2.3.1'
        ThenReturnedNoFoundPath
    }
}