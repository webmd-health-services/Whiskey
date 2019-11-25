
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

function GivenImport
{
    $taskParameter['Import'] = 'true'
}

function GivenModule
{
    Param(
        [String]$Module
    )

    $taskParameter['Name'] = $Module
}

function GivenVersion
{
    param(
        [String]$Version
    )
    $taskParameter['Version'] = $Version
}

function GivenPath
{
    param(
        $Path
    )

    $taskParameter['Path'] = $Path
}

function GivenPrereleaseAllowed
{
    $taskParameter['AllowPrerelease'] = 'true'
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

function WhenTaskRun
{
    [CmdletBinding()]
    param()


    $script:modulePath = Join-Path -Path $context.BuildRoot -ChildPath $TestPSModulesDirectoryName
    if( $taskParameter['Path'] )
    {
        $script:modulePath = Join-Path $context.BuildRoot -ChildPath $taskParameter['Path']
    }
    $script:modulePath = Join-Path -Path $modulePath -ChildPath $taskParameter['Name']
    $script:modulePath = [IO.Path]::GetFullPath($modulePath)

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
    param(
        $AtVersion,
        $InDirectory = $TestPSModulesDirectoryName
    )

    $version = '*.*.*'
    $prerelease = ''
    if( $AtVersion -match '^(\d+\.\d+\.\d+)(-(.*))?$' )
    {
        $version = $Matches[1]
        $prerelease = $Matches[3]
    }

    $modulePath = Join-Path -Path $testRoot -ChildPath $InDirectory
    $modulePath = Join-Path -Path $modulePath -ChildPath $taskParameter['Name']
    $modulePath = Join-Path -Path $modulePath -ChildPath $version
    $modulePath = Join-Path -Path $modulePath -ChildPath ('{0}.psd1' -f $taskParameter['Name'])
    $modulePath | Should -Exist

    $module = Test-ModuleManifest -Path $modulePath
    if( $prerelease )
    {
        $module.PrivateData.PSData.Prerelease | Should -Be $prerelease
    }
    else
    {
        if( ($module.PrivateData.PSData | Get-Member 'Prerelease') )
        {
            $module.PrivateData.PSData.Prerelease | Should -BeNullOrEmpty
        }
    }
}

function ThenModuleImported
{
    param(
        [Parameter(Mandatory)]
        [String]$Name
    )

    $module = Get-Module -Name $Name 
    $module | Should -Not -BeNullOrEmpty
    # Cross-platform path generation
    $expectedPath = Join-Path -Path $testRoot -ChildPath $TestPSModulesDirectoryName
    $expectedPath = Join-Path -Path $expectedPath -ChildPath $Name
    $expectedPath = Join-Path -Path $expectedPath -ChildPath '*'
    $module.Path | Should -BeLike $expectedPath
}

function ThenModuleNotImported
{
    param(
        [Parameter(Mandatory)]
        [String]$Name
    )

    Get-Module -Name $Name | Should -BeNullOrEmpty
}

function ThenModuleNotInstalled
{
    param(
        $InDirectory = $TestPSModulesDirectoryName
    )

    $modulePath = Join-Path -Path $testRoot -ChildPath $InDirectory
    $modulePath = Join-Path -Path $modulePath -ChildPath $taskParameter['Name']
    $modulePath = Join-Path -Path $modulePath -ChildPath ('*.*.*\{0}.psd1' -f $taskParameter['Name'])
    $modulePath | Should -Not -Exist
}

function ThenErrorShouldBeThrown
{
    param(
        [String]$Message
    )

    $Global:Error | Should -Match $Message
}

Describe 'GetPowerShellModule.when given a module Name' {
    AfterEach { Reset }
    W''
        Init
        Get-Module 'Zip' | Remove-Module -Force
        GivenModule 'Zip'
        WhenTaskRun
        ThenModuleInstalled
        ThenModuleNotImported 'Zip'
    }
}

Describe 'GetPowerShellModule.when given a module Name and Version' {
    AfterEach { Reset }
    It 'should install that version of the module' {
        Init
        GivenModule 'Pester'
        GivenVersion '3.4.0'
        WhenTaskRun
        ThenModuleInstalled -AtVersion '3.4.0'
    }
}

Describe 'GetPowerShellModule.when given a Name and a wildcard Version' {
    AfterEach { Reset }
    It 'should save the module at latest version that matches the wildcard' {
        Init
        GivenModule 'Pester'
        GivenVersion '3.3.*'
        WhenTaskRun
        ThenModuleInstalled -AtVersion '3.3.9'
    }
}

Describe 'GetPowerShellModule.when an invalid module Name is requested' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModule 'bad mod'
        GivenVersion '3.4.0'
        GivenNonExistentModule
        WhenTaskRun  -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown 'Failed to find PowerShell module bad mod'
        ThenModuleNotInstalled
    }
}

Describe 'GetPowerShellModule.when given an invalid Version' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModule 'Pester'
        GivenVersion '0.0.0'
        GivenNonExistentModule
        WhenTaskRun -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown "Failed to find PowerShell module Pester at version 0.0.0"
        ThenModuleNotInstalled
    }
}

Describe 'GetPowerShellModule.when missing Name property' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenTaskRun -ErrorAction SilentlyContinue
        ThenErrorShouldBeThrown 'Property\ "Name"\ is mandatory'
    }
}

Describe 'GetPowerShellModule.when called with clean mode' {
    AfterEach { Reset }
    It 'should remove installed modules that match version' {
        Init
        GivenModule 'Rivet'
        GivenCleanMode
        WhenTaskRun
        ThenModuleNotInstalled
    }
}

Describe 'GetPowerShellModule.when allowing prerelease versions' {
    AfterEach { Reset }
    It 'should install a prelease version' {
        Init
        GivenModule 'Whiskey'
        GivenVersion '0.43.*-*'
        GivenPrereleaseAllowed
        WhenTaskRun
        ThenModuleInstalled -AtVersion '0.43.0-beta1416'
    }
}

Describe 'GetPowerShellModule.when installing to custom directory' {
    AfterEach { Reset }
    It 'should install to a custom directory' {
        Init
        GivenModule 'Zip'
        GivenPath 'FubarSnafu'
        WhenTaskRun
        ThenModuleInstalled -InDirectory 'FubarSnafu'
        GivenCleanMode
        WhenTaskRun
        ThenModuleNotInstalled -InDirectory 'FubarSnafu'
    }
}

Describe 'GetPowerShellModule.when importing module after installation' {
    AfterEach { Reset }
    It 'should import module into global scope' {
        Init
        Import-Module -Name (Join-Path $PSScriptRoot -ChildPath ('..\{0}\Glob' -f $TestPSModulesDirectoryName) -Resolve) -Force
        GivenImport
        GivenModule 'Glob'
        WhenTaskRun
        ThenModuleInstalled
        ThenModuleImported 'Glob'
    }
}