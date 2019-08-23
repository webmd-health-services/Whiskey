Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$moduleName = $null
$moduleVersion = $null
$output = $null

function Init
{
    $Global:Error.Clear()
    $script:moduleName = $null
    $script:moduleVersion = $null
    $script:output = $null
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

function WhenResolvingPowerShellModule
{
    [CmdletBinding()]
    param()

    $parameters = $PSBoundParameters
    $parameters['Name'] = $moduleName

    if( $moduleVersion )
    {
        $parameters['Version'] = $moduleVersion
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' -Parameter $parameter
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
    It 'should find it' {
        Init
        GivenName 'Pester'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name "Pester" and Version "4.1.1"' {
    It 'should resolve that version' {
        Init
        GivenName 'Pester'
        GivenVersion '4.1.1'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.1.1'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given Version wildcard' {
    It 'should resolve the latest version that matches the wildcard' {
        Init
        GivenName 'Pester'
        GivenVersion '4.1.*'
        WhenResolvingPowerShellModule
        ThenReturnedModuleInfoObject
        ThenReturnedModule 'Pester' -AtVersion '4.1.*'
        ThenNoErrors
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module that does not exist' {
    It 'should fail' {
        Init
        GivenModuleDoesNotExist
        WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to find module'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when Find-Module returns module from two repositories' {
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
