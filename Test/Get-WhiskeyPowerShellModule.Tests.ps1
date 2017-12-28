
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PackageManagement' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PowerShellGet' -Resolve)

$context = $null
$modulePath = $null
$taskParameter = @{}

function Init
{
    $Global:Error.Clear()
    $script:modulePath = $null
    $script:taskParameter = @{}
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function GivenModule
{
    Param(
        [string]
        $Module
    )
    $script:taskParameter['Name'] = $Module

    $script:modulePath = Join-path -Path $context.BuildRoot -ChildPath 'Modules'
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
    It ('should install the module ''{0}''' -f $taskParameter['Name']) {
        $modulePath | Should -Exist
    }
}

function ThenModuleInstalledAtVersion
{
    param(
        $Version
    )

    $moduleVersionPath = Join-Path -Path $modulePath -ChildPath $Version

    It ('should install module at version ''{0}''' -f $Version) {
        $moduleVersionPath | Should -Exist
    }
}

function ThenModuleShouldNotExist
{
    It 'should not install the module' {
        $modulePath | Should -Not -Exist
    }
}

function ThenErrorShouldBeThrown
{
    param(
        [string]
        $Message
    )

    It ('should throw an error that matches /{0}/' -f $Message) {
        $Global:Error | Should -Match $Message
    }
}
Describe 'GetPowerShellModule.when given a module Name' {
    Init
    GivenModule 'Pester'
    WhenPowershellModuleIsRan
    ThenModuleInstalled
}

Describe 'GetPowerShellModule.when given a module Name and Version' {
    Init
    GivenModule 'Pester'
    GivenVersion '3.4.0'
    WhenPowershellModuleIsRan
    ThenModuleInstalled
    ThenModuleInstalledAtVersion '3.4.0'
}

Describe 'GetPowerShellModule.when given a Name and a wildcard Version' {
    Init
    GivenModule 'Pester'
    GivenVersion '3.3.*'
    WhenPowershellModuleIsRan
    ThenModuleInstalled
    ThenModuleInstalledAtVersion '3.3.9'
}

Describe 'GetPowerShellModule.when an invalid module Name is requested' {
    Init
    GivenModule 'bad mod'
    GivenVersion '3.4.0'
    GivenNonExistentModule
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown 'Failed to find module bad mod'
    ThenModuleShouldNotExist
}

Describe 'GetPowerShellModule.when given an invalid Version' {
    Init
    GivenModule 'Pester'
    GivenVersion '0.0.0'
    GivenNonExistentModule
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown -errorMessage "Failed to download Pester 0.0.0"
    ThenModuleShouldNotExist
}

Describe 'GetPowerShellModule.when missing Name property' {
    Init
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown "Please Add a Name Property for which PowerShell Module you would like to get."
}

Describe 'GetPowerShellModule.when called with clean mode' {
    Init
    GivenModule 'Pester'
    GivenCleanMode
    WhenPowershellModuleIsRan
    ThenModuleShouldNotExist
}