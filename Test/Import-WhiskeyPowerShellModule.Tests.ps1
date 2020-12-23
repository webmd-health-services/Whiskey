Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$output = $null
$installedModule = $null
$testRoot = $null

function Init
{
    $Global:Error.Clear()
    $script:installedModule = $null
    $script:testRoot = New-WhiskeyTestRoot
}

function GivenModuleInstalled
{
    param(
        [Parameter(Mandatory)]
        [String]$Name,

        [Version]$Version = '0.0.0'
    )

    $script:installedModule = 
        [Management.Automation.PSModuleInfo]::New($false) |
        Add-Member -Name 'Name' -MemberType NoteProperty -Value $Name -Force -PassThru |
        Add-Member -Name 'Version' -MemberType NoteProperty -Value $Version -Force -PassThru |
        Add-Member -Name 'MockObject' -MemberType NoteProperty -Value $true -PassThru 
}

function ThenImportsModule
{
    param(
        [Parameter(Mandatory)]
        [String]$Named,

        [String]$AtVersion = '0.0.0'
    )

    $filters = @(
        { $ModuleInfo.Name | Should -Be $Named ; $true },
        { $ModuleInfo.Version | Should -Be $AtVersion ; $true },
        { $ModuleInfo.MockObject | Should -BeTrue ; $true }
    )

    foreach( $filter in $filters )
    {
        Assert-MockCalled -CommandName 'Import-Module' -ModuleName 'Whiskey' -ParameterFilter $filter -Times 1 -Exactly
    }
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function WhenImportingPowerShellModule
{
    [CmdletBinding()]
    param(
        [String] $Name,
        [String] $Version,
        [scriptblock]$MockImportWith = {}
    )

    Mock -CommandName 'Import-Module' -ModuleName 'Whiskey' -MockWith $MockImportWith

    $installedModule = $script:installedModule
    if( $installedModule )
    {
        Mock -CommandName 'Get-WhiskeyPSModule' `
             -ModuleName 'Whiskey' `
             -ParameterFilter ([scriptblock]::Create("{ throw ""$($installedModule.Name)"" ; `$Name -eq ""$($installedModule.Name)"" }")) `
             -MockWith { return $installedModule }.GetNewClosure()
    }
    else
    {
        Mock -CommandName 'Get-WhiskeyPSModule' -ModuleName 'Whiskey'
    }

    $parameter = @{
        'Name' = $Name;
        'Version' = $Version;
        'PSModulesRoot' = $testRoot;
    }

    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyPowerShellModule' -Parameter $parameter
}

Describe 'Import-WhiskeyPowerShellModule.when module is installed' {
    it 'should import global module' {
        init
        GivenModuleInstalled 'Zip'
        WhenImportingPowerShellModule -Name 'Zip'
        ThenImportsModule 'Zip'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when specific version of a module is installed' {
    it 'should import global module' {
        init
        GivenModuleInstalled 'Zip' -Version '9.8.7'
        WhenImportingPowerShellModule -Name 'Zip' -Version '9.8.7'
        ThenImportsModule 'Zip' -AtVersion '9.8.7'
        ThenNoErrors
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module is not installed' {
    AfterEach { $Global:ErrorActionPreference = 'Continue' }
    It 'should throw an error' {
        Init
        $Global:ErrorActionPreference = 'Stop' 
        { WhenImportingPowerShellModule -Name 'Zip' } | Should -Throw 'that module isn''t installed'
    }
}

Describe 'Import-WhiskeyPowerShellModule.when module writes silent errors during import' {
    It 'should remove those errors' {
        Init
        GivenModuleInstalled 'Zip'
        WhenImportingPowerShellModule 'Zip' -MockImportWith { Write-Error 'Fubar!' -ErrorAction SilentlyContinue }
        $Global:Error | Should -BeNullOrEmpty
    }
}