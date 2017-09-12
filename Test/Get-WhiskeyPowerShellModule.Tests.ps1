
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$taskParameter = @{}
$moduleName = 'Carbon'
$invalidModuleName = 'No Module Here'
$version = '2.5.0'
$badVersion = '0.0.0'
function GivenContext 
{
    $script:taskParameter = @{}
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function GivenModule
{
    $script:taskParameter['Name'] = $moduleName
}

function GivenVersion 
{
    $script:taskParameter['Version'] = $version
}

function GivenInvalidVersion 
{
    $script:taskParameter['Version'] = $badVersion
}

function GivenInvalidModule 
{
    $script:taskParameter['Name'] = $invalidModuleName
}

function GivenCleanMode
{
    $script:context.Runmode = 'clean'
}
function WhenPowershellModuleIsRan
{
    $global:Error.clear()
    try
    {
        Get-whiskeyPowershellModule -TaskContext $context -TaskParameter $taskParameter
    }
    catch
    {
        write-error $_
    }
}

function ThenModuleShouldBeInstalled
{
    $modulePath = Join-path -Path 'Modules' -ChildPath $moduleName
    it 'should have installed the module' {
        Join-path -path $context.BuildRoot -ChildPath $modulePath | should -Exist
    }
    
}

function ThenModuleShouldNotBeInstalled
{
    $modulePath = Join-path -Path 'Modules' -ChildPath $moduleName
    it 'should have uninstalled the module' {
        Join-path -path $context.BuildRoot -ChildPath $modulePath | should -not -Exist
    }
}

function ThenErrorShouldBeThrown
{
    param(
        [string]
        $errorMessage
    )
    it ('should throw an error that matches {0}' -f $errorMessage){
        $Global:Error | where-object {$_ -match $errorMessage } | Should -not -BeNullOrEmpty
    }
}
Describe 'Get-WhiskeyPowerShellModule.when a valid module is requested without version parameter' {
    GivenContext
    GivenModule
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled
}

Describe 'Get-WhiskeyPowerShellModule.when a valid module is requested with version parameter' {
    GivenContext
    GivenModule
    GivenVersion
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled
}

Describe 'Get-WhiskeyPowerShellModule.when an invalid module name is requested' {
    GivenContext
    GivenVersion
    GivenInvalidModule
    WhenPowershellModuleIsRan
    ThenErrorShouldBeThrown -errorMessage 'No match was found for the specified search criteria and module name'
}

Describe 'Get-WhiskeyPowerShellModule.when called with invalid version' {
    GivenContext
    GivenModule
    GivenInvalidVersion
    WhenPowershellModuleIsRan
    ThenErrorShouldBeThrown -errorMessage "Failed to find module Carbon version 0.0.0"
}

Describe 'Get-WhiskeyPowerShellModule.when called with missing name' {
    GivenContext
    WhenPowershellModuleIsRan
    ThenErrorShouldBeThrown -errorMessage "Please"
}

Describe 'Get-WhiskeyPowerShellModule.when called with clean mode' {
    GivenContext
    GivenModule
    GivenCleanMode
    WhenPowershellModuleIsRan
    ThenModuleShouldNotBeInstalled
}