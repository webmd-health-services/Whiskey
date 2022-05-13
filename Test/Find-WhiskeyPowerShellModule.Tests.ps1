Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# If you want to upgrade the PackageManagement and PowerShellGet versions, you must also update:
# * Whiskey\Functions\Find-WhiskeyPowerShellModule.ps1
# * prism.json
$packageManagementVersion = '1.4.7'
$powerShellGetVersion = '2.2.5'

$moduleName = $null
$moduleVersion = $null
$output = $null
$testRoot = $null
$originalPSModulePath = $null
$packageManagementModulesNotInstalled = $false

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

function GivenPkgMgmtModulesInstalled
{
    Initialize-WhiskeyTestPSModule -BuildRoot $testRoot
    Resolve-Path -Path (Join-Path -Path $testRoot -ChildPath "$($TestPSModulesDirectoryName)\*\*") |
        Join-Path -ChildPath 'notinstalled' |
        ForEach-Object { New-Item -Path $_ -ItemType 'File' }
    $script:packageManagementModulesNotInstalled = $false
}

function GivenPkgMgmtModulesNotInstalled
{
    $psmodulesPath = Join-Path -Path $testRoot -ChildPath 'PSModules'
    if( (Test-Path -Path $psmodulesPath) )
    {
        Remove-Item -Path $psmodulesPath -Recurse -Force
    }
    $script:packageManagementModulesNotInstalled = $true
}

function Init
{
    $Global:Error.Clear()
    $script:moduleName = $null
    $script:moduleVersion = $null
    $script:output = $null
    $script:testRoot = New-WhiskeyTestRoot
    $script:packageManagementModulesNotInstalled = $false
    Reset-WhiskeyPSModulePath
}

function Reset
{
    Reset-WhiskeyTestPSModule
    Invoke-WhiskeyPrivateCommand -Name 'Unregister-WhiskeyPSModulePath' -Parameter @{ 'PSModulesRoot' = $testRoot }
    Reset-WhiskeyPSModulePath
}

function ThenPkgManagementModules
{
    [CmdletBinding(DefaultParameterSetName='ImportedAndOrInstalled')]
    param(
        [Parameter(Position=0)]
        [String]$Named,

        [Parameter(Mandatory,ParameterSetName='NotInstalled')]
        [Parameter(Mandatory,ParameterSetName='NotImported')]
        [switch]$Not,

        [Parameter(Mandatory,ParameterSetName='NotImported')]
        [Parameter(ParameterSetName='ImportedAndOrInstalled')]
        [switch]$Imported,

        [Parameter(Mandatory,ParameterSetName='NotInstalled')]
        [Parameter(ParameterSetName='ImportedAndOrInstalled')]
        [switch]$Installed
    )

    if( $Imported )
    {
        $times = 1
        if( $Not )
        {
            $times = 0
        }

        $modulesRoot = $script:testRoot

        if( -not $Named -or $Named -eq 'PackageManagement' )
        {
            $pkgMgmtVersion = $script:packageManagementVersion
            Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' `
                            -ModuleName 'Whiskey' `
                            -Times $times `
                            -Exactly `
                            -ParameterFilter { 
                                    $Name -eq 'PackageManagement' -and `
                                    $PSModulesRoot -eq $modulesRoot -and `
                                    $Version -eq $pkgMgmtVersion 
                                }
        }

        if( -not $Named -or $Named -eq 'PowerShellGet' )
        {
            $psGetVersion = $script:powerShellGetVersion
            Assert-MockCalled -CommandName 'Import-WhiskeyPowerShellModule' `
                            -ModuleName 'Whiskey' `
                            -Times $times `
                            -Exactly `
                            -ParameterFilter { 
                                    $Name -eq 'PowerShellGet' -and `
                                    $PSModulesRoot -eq $modulesRoot -and `
                                    $Version -eq $psGetVersion 
                            }
        }
    }

    if( $Installed )
    {
        if( -not $Named -or $Named -eq 'PackageManagement' )
        {
            $pkgMgmtPath = Join-Path -Path $testRoot -ChildPath "PSModules\PackageManagement\$($packageManagementVersion)"
            Join-Path -Path $pkgMgmtPath -ChildPath "notinstalled" | Should -Not:(-not $Not) -Exist
            Join-Path -Path $pkgMgmtPath -ChildPath "PackageManagement.psd1" | Should -Exist
        }

        if( -not $Named -or $Named -eq 'PowerShellGet' )
        {
            $pwshGetPath = Join-Path -Path $testRoot -ChildPath "PSModules\PowerShellGet\$($powerShellGetVersion)"
            Join-Path -Path $pwshGetPath -ChildPath "notinstalled" | Should -Not:(-not $Not) -Exist
            Join-Path -Path $pwshGetPath -ChildPath "PowerShellGet.psd1" | Should -Exist
        }
    }
}

function ThenReturnedModule
{
    param(
        [Parameter(Mandatory)]
        [String]$Name,
        [String]$AtVersion
    )

    $output | Should -Not -BeNullOrEmpty
    $output | Should -HaveCount 1

    $output.Name | Should -Be $Name

    if( $AtVersion )
    {
        $output.Version.ToString() | Should -BeLike $AtVersion
    }

    $output | Get-Member -Name 'Version' | Should -Not -BeNullOrEmpty
    $output | Get-Member -Name 'Repository' | Should -Not -BeNullOrEmpty
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

function WhenResolvingPowerShellModule
{
    [CmdletBinding()]
    param(
    )

    Mock -CommandName 'Import-WhiskeyPowershellModule' -ModuleName 'Whiskey'

    $parameter = @{
        'Name' = $moduleName;
        'BuildRoot' = $testRoot;
    }

    if( $moduleVersion )
    {
        $parameter['Version'] = $moduleVersion
    }

    if( $packageManagementModulesNotInstalled )
    {
        Mock -CommandName 'Get-WhiskeyPSModule' `
             -Module 'Whiskey' `
             -ParameterFilter { $Name -in @('PackageManagement', 'PowerShellGet') } `
             -MockWith { return $false }
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Find-WhiskeyPowerShellModule' -Parameter $parameter -ErrorAction $ErrorActionPreference
}

Describe 'Find-WhiskeyPowerShellModule.when package management modules are not installed' {
    AfterEach { Reset }
    It 'should find it' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalled
        WhenResolvingPowerShellModule
        ThenPkgManagementModules -Imported -Installed
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Find-WhiskeyPowerShellModule.when given module Name "Pester" and Version "4.3.1"' {
    AfterEach { Reset }
    It 'should resolve that version' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.1'
        GivenPkgMgmtModulesInstalled
        WhenResolvingPowerShellModule
        ThenPkgManagementModules -Imported
        ThenPkgManagementModules -Not -Installed
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Find-WhiskeyPowerShellModule.when given Version wildcard' {
    AfterEach { Reset }
    It 'should resolve the latest version that matches the wildcard' {
        Init
        GivenName 'Pester'
        GivenVersion '4.3.*'
        GivenPkgMgmtModulesInstalled
        WhenResolvingPowerShellModule
        ThenPkgManagementModules -Imported
        ThenPkgManagementModules -Not -Installed
        ThenReturnedModule 'Pester' -AtVersion '4.3.1'
        ThenNoErrors
    }
}

Describe 'Find-WhiskeyPowerShellModule.when given module that does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenModuleDoesNotExist
        GivenPkgMgmtModulesInstalled
        WhenResolvingPowerShellModule -ErrorAction SilentlyContinue
        ThenPkgManagementModules -Imported
        ThenPkgManagementModules -Not -Installed
        ThenErrorMessage 'Failed to find'
        ThenReturnedNothing
    }
}

Describe 'Find-WhiskeyPowerShellModule.when Find-Module returns module from two repositories' {
    AfterEach { Reset }
    It 'should pick one' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesInstalled
        GivenReturnedModuleFromTwoRepositories
        WhenResolvingPowerShellModule
        ThenPkgManagementModules -Imported
        ThenPkgManagementModules -Not -Installed
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}

Describe 'Find-WhiskeyPowerShellModule.when module remnants get left behind' {
    AfterEach { Reset }
    It 'should clear out the old directory' {
        Init
        GivenName 'Pester'
        GivenPkgMgmtModulesNotInstalled
        $testModulesRoot = Join-Path -Path $testRoot -ChildPath 'PSModules'
        $junkPsd1Paths = @(
            (Join-Path -Path $testModulesRoot -ChildPath "PackageManagement\$($packageManagementVersion)\notinstalled"),
            (Join-Path -Path $testModulesRoot -ChildPath "PowerShellGet\$($powershellGetVersion)\notinstalled")
        )
        foreach( $path in $junkPsd1Paths )
        {
            New-Item -Path $path -ItemType 'File' -Force
        }
        WhenResolvingPowerShellModule
        ThenPkgManagementModules -Imported
        ThenPkgManagementModules 'PackageManagement' -Installed
        ThenPkgManagementModules 'PowerShellGet' -Installed
        ThenReturnedModule 'Pester'
        ThenNoErrors
    }
}
