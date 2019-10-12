Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$moduleName = $null
$moduleVersion = $null
$output = $null
$testRoot = $null

function Init
{
    $Global:Error.Clear()
    $script:moduleName = $null
    $script:moduleVersion = $null
    $script:output = $null
    $script:testRoot = New-WhiskeyTestRoot
}

function GivenName
{
    param(
        $Name
    )
    $script:moduleName = $Name
}

function GivenVersion
{
    param(
        $Version
    )
    $script:moduleVersion = $Version
}

function GivenReturnedModuleFromTwoRepositories
{
    $pesterRepo1 = Find-Module -Name 'Pester' | Select-Object -First 1
    $pesterRepo2 = $pesterRepo1.PSObject.Copy()
    $pesterRepo2.Repository = 'Another PowerShellGet Repository'

    $moduleOutput = @($pesterRepo1, $pesterRepo2)

    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey' -MockWith { $moduleOutput }.GetNewClosure()
}

function GivenModuleDoesNotExist
{
    $script:moduleName = 'nonexistentmodule'
    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey'
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function WhenResolvingPowerShellModule
{
    [CmdletBinding()]
    param(
        [Switch]$SkipCaching
    )

    $parameter = @{
        'Name' = $moduleName;
        'BuildRoot' = $testRoot;
    }

    if( $moduleVersion )
    {
        $parameter['Version'] = $moduleVersion
    }

    if( -not $SkipCaching )
    {
        # Put the PackageManagement and PowerShellGet modules in place so they don't get installed and make the tests take a long time.
        Initialize-WhiskeyTestPSModule -BuildRoot $testRoot
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

function ThenReturnedModuleInfoObject
{
    $count = $output | Measure-Object | Select-Object -ExpandProperty 'Count'
    $count | Should -Be 1
    $output | Get-Member -Name 'Version' | Should -Not -BeNullOrEmpty
    $output | Get-Member -Name 'Repository' | Should -Not -BeNullOrEmpty
}

function ThenReturnedModule
{
    param(
        $Name,
        $AtVersion
    )

    $output.Name | Should -Be $Name

    if ($AtVersion)
    {
        $output.Version.ToString() | Should -BeLike $AtVersion
    }
}

function ThenReturnedNothing
{
    $output | Should -BeNullOrEmpty
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

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name "Pester"' {
    AfterEach { Reset }
    It 'should find it' {
        Init
        GivenName 'Pester'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name "Pester" and Version "4.3.1"' {
    AfterEach { Reset }
    It 'should resolve that version' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.1'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given Version wildcard' {
    AfterEach { Reset }
    It 'should resolve the latest version that matches the wildcard' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.*'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module that does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModuleDoesNotExist
        WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to find'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when Find-Module returns module from two repositories' {
    AfterEach { Reset }
    It 'should pick one' {
        Init
        GivenName 'Pester'
        GivenReturnedModuleFromTwoRepositories
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when package management modules aren''t installed' {
    AfterEach { Reset }
    It 'should install package management modules' {
        Init
        GivenName 'Pester'
        WhenResolvingPowerShellModule -SkipCaching
        Join-Path -Path $testRoot -ChildPath ('{0}\PackageManagement\1.4.4' -f $PSModulesDirectoryName) | Should -Exist
        Join-Path -Path $testRoot -ChildPath ('{0}\PowerShellGet\2.2.1' -f $PSModulesDirectoryName) | Should -Exist
    }
}