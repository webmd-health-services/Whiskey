Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\PowerShellGet' -Resolve)

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
    $pesterRepo1 = Find-Module -Name 'Pester'
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

function GivenVersionDoesNotExist
{
    $script:moduleName = 'nonexistentmodule'
    $script:moduleVersion = '1.0.0'
    Mock -CommandName 'Find-Module' -ModuleName 'Whiskey'
}

function WhenResolvingPowerShellModule
{
    [CmdletBinding()]
    param()

    $versionParam = @{}
    if ($moduleVersion)
    {
        $versionParam['Version'] = $moduleVersion
    }

    $script:output = Resolve-WhiskeyPowerShellModule -Name $moduleName @versionParam
}

function ThenReturnedModuleInfoObject
{
    It 'should only return 1 object' {
        $count = $output | Measure-Object | Select-Object -ExpandProperty 'Count'
        $count | Should -Be 1
    }

    It 'should contain a ''Version'' property' {
        $output | Get-Member -Name 'Version' | Should -Not -BeNullOrEmpty
    }

    It 'should contain a ''Repository'' property' {
        $output | Get-Member -Name 'Repository' | Should -Not -BeNullOrEmpty
    }
}

function ThenReturnedModule
{
    param(
        $Name,
        $AtVersion
    )

    It ('should return the ''{0}'' module' -f $Name) {
        $output.Name | Should -Be $Name
    }

    if ($AtVersion)
    {
        It ('should be Version ''{0}''' -f $AtVersion) {
            $output.Version.ToString() | Should -BeLike $AtVersion
        }
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $output | Should -BeNullOrEmpty
    }
}

function ThenNoErrors
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenErrorMessage
{
    param(
        $Message
    )

    It ('should write error message /{0}/' -f $Message) {
        $Global:Error | Should -Match $Message
    }
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name ''Pester''' {
    Init
    GivenName 'Pester'
    WhenResolvingPowerShellModule
    ThenReturnedModuleInfoObject
    ThenReturnedModule 'Pester'
    ThenNoErrors
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module Name ''Pester'' and Version ''4.1.1''' {
    Init
    GivenName 'Pester'
    GivenVersion '4.1.1'
    WhenResolvingPowerShellModule
    ThenReturnedModuleInfoObject
    ThenReturnedModule 'Pester' -AtVersion '4.1.1'
    ThenNoErrors
}

Describe 'Resolve-WhiskeyPowerShellModule.when given Version wildcard' {
    Init
    GivenName 'Pester'
    GivenVersion '4.1.*'
    WhenResolvingPowerShellModule
    ThenReturnedModuleInfoObject
    ThenReturnedModule 'Pester' -AtVersion '4.1.*'
    ThenNoErrors
}

Describe 'Resolve-WhiskeyPowerShellModule.when given module that does not exist' {
    Init
    GivenModuleDoesNotExist
    WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
    ThenErrorMessage 'Failed to find module'
    ThenReturnedNothing
}

Describe 'Resolve-WhiskeyPowerShellModule.when given Version that does not exist' {
    Init
    GivenVersionDoesNotExist
    WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
    ThenErrorMessage 'Failed to find module'
    ThenReturnedNothing
}

Describe 'Resolve-WhiskeyPowerShellModule.when Find-Module returns module from two repositories' {
    Init
    GivenName 'Pester'
    GivenReturnedModuleFromTwoRepositories
    WhenResolvingPowerShellModule
    ThenReturnedModuleInfoObject
    ThenReturnedModule 'Pester'
    ThenNoErrors
}
