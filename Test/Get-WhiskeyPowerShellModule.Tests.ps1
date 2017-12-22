
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PackageManagement' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PowerShellGet' -Resolve)

$context = $null
$taskParameter = @{}

function Init
{
    $Global:Error.Clear()
    $script:taskParameter = @{}
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function GivenModule
{
    Param(
        [String]
        $module
    )
    $script:taskParameter['Name'] = $module
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
        write-error $_
    }
}

function ThenModuleShouldBeInstalled
{
    param(
        [String]
        $module,
        [String]
        $AtVersion
    )
    $modulePath = Join-path -Path 'Modules' -ChildPath $module
    $modulePath = Join-path -path $context.BuildRoot -ChildPath $modulePath
    it 'should have installed the module' {
        $modulePath | should -Exist
    }

    if ($AtVersion)
    {
        it ('Should have installed version {0}' -f $AtVersion) {
            Find-Module -Name 'Pester' -AllVersions | Where-Object { $_.Version -match $AtVersion } | should -not -BeNullOrEmpty
        }
    }
}

function ThenModuleShouldNotExist
{
    $modulePath = Join-path -Path 'Modules' -ChildPath $taskParameter['Name']
    it 'should not have the module installed' {
        Join-path -path $context.BuildRoot -ChildPath $modulePath | should -not -Exist
    }
}

function ThenErrorShouldBeThrown
{
    param(
        [string]
        $errorMessage
    )
    it ('should throw an error that matches ''{0}''' -f $errorMessage){
        $Global:Error | where-object {$_ -match $errorMessage } | Should -not -BeNullOrEmpty
    }
}
Describe 'GetPowerShellModule.when a valid module is requested without version parameter' {
    Init
    GivenModule -module 'Pester'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester'
}

Describe 'GetPowerShellModule.when a valid module is requested with version parameter' {
    Init
    GivenModule -module 'Pester'
    GivenVersion -version '3.4.0'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester' -AtVersion '3.4.0'
}

Describe 'GetPowerShellModule.when a valid module is requested with wildcard version' {
    Init
    GivenModule -module 'Pester'
    GivenVersion -version '3.3.*'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester' -AtVersion '3.3.14'
}

Describe 'GetPowerShellModule.when an invalid module name is requested' {
    Init
    GivenModule -Module 'bad mod'
    GivenVersion -Version '3.4.0'
    GivenNonExistentModule
    WhenPowershellModuleIsRan  -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown 'Failed to find module bad mod'
    ThenModuleShouldNotExist
}

Describe 'GetPowerShellModule.when called with invalid version' {
    Init
    GivenModule -Module 'Pester'
    GivenVersion -Version '0.0.0'
    GivenNonExistentModule
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown "Failed to find module Pester version 0.0.0"
    ThenModuleShouldNotExist
}

Describe 'GetPowerShellModule.when called with missing name' {
    Init
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown "Please Add a Name Property for which PowerShell Module you would like to get."
    ThenModuleShouldNotExist
}

Describe 'GetPowerShellModule.when called with clean mode' {
    Init
    GivenModule -module 'Pester'
    GivenCleanMode
    WhenPowershellModuleIsRan
    ThenModuleShouldNotExist
}