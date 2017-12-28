
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PackageManagement' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PowerShellGet' -Resolve)

$context = $null
$taskParameter = @{}
function GivenContext 
{
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

function GivenCleanMode
{
    $script:context.Runmode = 'clean'
}

function WhenPowershellModuleIsRan
{
    [CmdletBinding()]
    param(
    )

    $global:Error.clear()
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

    it ('Should have installed version {0}' -f $AtVersion) {
        Find-Module -Name 'Pester' -AllVersions | Where-Object { $_.Version -match $AtVersion } | should -not -BeNullOrEmpty
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
Describe 'Get-WhiskeyPowerShellModule.when a valid module is requested without version parameter' {
    GivenContext
    GivenModule -module 'Pester'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester'
}

Describe 'Get-WhiskeyPowerShellModule.when a valid module is requested with version parameter' {
    GivenContext
    GivenModule -module 'Pester'
    GivenVersion -version '3.4.0'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester' -AtVersion '3.4.0'
}

Describe 'Get-WhiskeyPowerShellModule.when a valid module is requested with wildcard version' {
    GivenContext
    GivenModule -module 'Pester'
    GivenVersion -version '3.3.*'
    WhenPowershellModuleIsRan
    ThenModuleShouldBeInstalled -module 'Pester' -AtVersion '3.3.14'
}

Describe 'Get-WhiskeyPowerShellModule.when an invalid module name is requested' {
    GivenContext
    GivenVersion -version '3.4.0'
    GivenModule -module 'bad mod'
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown -errorMessage 'No match was found for the specified search criteria and module name ''bad mod'''
    ThenModuleShouldNotExist
}

Describe 'Get-WhiskeyPowerShellModule.when called with invalid version' {
    GivenContext
    GivenModule -module 'Pester'
    GivenVersion  -version '0.0.0'
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown -errorMessage "Failed to download Pester 0.0.0"
    ThenModuleShouldNotExist
}

Describe 'Get-WhiskeyPowerShellModule.when called with missing name' {
    GivenContext
    WhenPowershellModuleIsRan -ErrorAction SilentlyContinue
    ThenErrorShouldBeThrown -errorMessage "Please Add a Name Property for which PowerShell Module you would like to get."
    ThenModuleShouldNotExist
}

Describe 'Get-WhiskeyPowerShellModule.when called with clean mode' {
    GivenContext
    GivenModule -module 'Pester'
    GivenCleanMode
    WhenPowershellModuleIsRan
    ThenModuleShouldNotExist
}