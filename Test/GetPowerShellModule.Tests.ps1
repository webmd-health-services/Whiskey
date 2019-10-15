
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$modulePath = $null
$taskParameter = @{}

function Init
{
    $Global:Error.Clear()
    $script:modulePath = $null
    $script:taskParameter = @{}

    $script:testRoot = New-WhiskeyTestRoot

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
}

function GivenModule
{
    Param(
        [string]
        $Module
    )
    $script:taskParameter['Name'] = $Module

    $script:modulePath = Join-path -Path $context.BuildRoot -ChildPath $PSModulesDirectoryName
    $script:modulePath = Join-path -Path $modulePath -ChildPath $taskParameter['Name']
}

function GivenVersion
{
    param(
        [string]
        $Version
    )
    $script:taskParameter['Version'] = $Version
}

function GivenNonExistentModule
{
    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey'
}

function GivenCleanMode
{
    $script:context.Runmode = 'clean'
}

function Reset
{
    Reset-WhiskeyTestPSModule
}
function WhenPowershellModuleIsRan
{
    [CmdletBinding()]
    param()

    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name "GetPowerShellModule"
    }
    catch
    {
        Write-Error -ErrorRecord $_
    }
}

function ThenModuleInstalled
{
    $modulePath | Should -Exist
}

function ThenModuleInstalledAtVersion
{
    param(
        $Version
    )

    $moduleVersionPath = Join-Path -Path $modulePath -ChildPath $Version

    $moduleVersionPath | Should -Exist
}

function ThenModuleShouldNotExist
{
    $modulePath | Should -Not -Exist
}

function ThenErrorShouldBeThrown
{
    param(
        [string]
        $Message
    )

    $Global:Error | Should -Match $Message
}

Describe 'GetPowerShellModule.when given a module Name' {
    AfterEach { Reset }
    It 'should install the lastest version of that module' {
        Init
        GivenModule 'Pester'
        WhenPowershellModuleIsRan
        ThenModuleInstalled
    }
}

Describe 'GetPowerShellModule.when given a module Name and Version' {
    AfterEach { Reset }
    It 'should install that version of the module' {
        Init
        GivenModule 'Pester'
        GivenVersion '3.4.0'
        WhenPowershellModuleIsRan
        ThenModuleInstalled
        ThenModuleInstalledAtVersion '3.4.0'
    }
}

Describe 'GetPowerShellModule.when given a Name and a wildcard Version' {
    AfterEach { Reset }
    It 'should save the module at latest version that matches the wildcard' {
        Init
        GivenModule 'Pester'
        GivenVersion '3.3.*'
        WhenPowershellModuleIsRan
        ThenModuleInstalled
        ThenModuleInstalledAtVersion '3.3.9'
    }
}

Describe 'GetPowerShellModule.when an invalid module Name is requested' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModule 'bad mod'
        GivenVersion '3.4.0'
        GivenNonExistentModule
        WhenPowershellModuleIsRan  -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown 'Failed to find PowerShell module bad mod'
        ThenModuleShouldNotExist
    }
}

Describe 'GetPowerShellModule.when given an invalid Version' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModule 'Pester'
        GivenVersion '0.0.0'
        GivenNonExistentModule
        WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown "Failed to find PowerShell module Pester at version 0.0.0"
        ThenModuleShouldNotExist
    }
}

Describe 'GetPowerShellModule.when missing Name property' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown 'Property\ "Name"\ is mandatory'
    }
}

Describe 'GetPowerShellModule.when called with clean mode' {
    AfterEach { Reset }
    It 'should remove installed modules that match version' {
        Init
        GivenModule 'Rivet'
        GivenCleanMode
        WhenPowershellModuleIsRan
        ThenModuleShouldNotExist
    }
}
