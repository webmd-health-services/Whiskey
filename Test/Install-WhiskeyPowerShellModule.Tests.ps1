
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

$packageManagementVersion = '1.4.5'
$powerShellGetVersion = '2.2.1'
$testRoot = $null
$powerShellModulesDirectoryName = 'PSModules'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Init
{
    param(
    )
    $script:testRoot = New-WhiskeyTestRoot
}

# Wrap private function so we can call it like it's public.
function Install-WhiskeyPowerShellModule
{
    [CmdletBinding()]
    param(
        $Name,
        $Version,
        $Path
    )

    Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyPowerShellModule' -Parameter $PSBoundParameters
}

function Invoke-PowershellInstall
{
    param(
        $ForModule,
        $Version,
        $ActualVersion
    )

    if( -not $ActualVersion )
    {
        $ActualVersion = $Version
    }

    $Global:Error.Clear()

    Push-Location -Path $testRoot
    try
    {
        $result = Install-WhiskeyPowerShellModule -Name $ForModule -Version $Version
    }
    finally
    {
        Pop-Location
    }

    $moduleRootPath = Join-Path -Path $testRoot -ChildPath ('PSModules\{0}' -f $ForModule)
    $result | Should -Not -BeNullOrEmpty
    $result | Should -Exist
    $result | Should -Be $moduleRootPath

    $errors = @()
    $module = Start-Job {
        Import-Module -Name $using:result -PassThru
    } | Wait-Job | Receive-Job -ErrorVariable 'errors'
    $errors | Should -BeNullOrEmpty
    $module.Version | Should -Be $ActualVersion
}

function Reset
{
    Remove-Module 'PowerShellGet' -Force -ErrorAction Ignore
    Remove-Module 'PackageManagement' -Force -ErrorAction Ignore
}
function ThenPackageManagementModulesInstalled
{
    ThenModuleInstalled 'PackageManagement' -AtVersion $packageManagementVersion 
    ThenModuleInstalled 'PowerShellGet' -AtVersion $powerShellGetVersion 
}

function ThenModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )
    
    Join-Path -Path $testRoot -ChildPath ('PSModules\{0}\{1}' -f $Name,$AtVersion) | Should -Exist
}

Describe 'Install-WhiskeyPowerShellModule.when installing and re-installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install package management modules and the module' {
        Init
        $Global:Error.Clear()

        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        ThenModuleInstalled 'Zip' -AtVersion '0.2.0'
        ThenPackageManagementModulesInstalled

        $Global:Error | Should -BeNullOrEmpty

        # Now, make sure the package management modules don't get re-installed.
        Mock -CommandName 'Start-Job' -ModuleName 'Whiskey'
        Invoke-PowerShellInstall -ForModule 'Zip' -Version '0.2.0'
        Assert-MockCalled -CommandName 'Start-Job' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and omitting patch number' {
    AfterEach { Reset }
    It 'should install at patch number 0' {
        Init
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2' -ActualVersion '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module omitting Version' {
    AfterEach { Reset }
    It 'should install the latest version' {
        Init
        $module = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' -Parameter @{ 'Name' = 'Zip' }
        Invoke-PowershellInstall -ForModule 'Zip' -Version '' -ActualVersion $module.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module using wildcard version' {
    AfterEach { Reset }
    It 'should resolve to the latest version that matches the wildcard' {
        Init
        $module = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' `
                                               -Parameter @{ 'Version' = '0.*'; 'Name' = 'Zip' }
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.*' -ActualVersion $module.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install the module' {
        Init
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and the version doesn''t exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Path $testRoot -Name 'Pester' -Version '3.0.0' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find module' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and version parameter is empty' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Path $testRoot -Name 'Fubar' -Version '' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find module' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is already installed' {
    AfterEach { Reset }
    It 'should install the new version' {
        Init
        Install-WhiskeyPowerShellModule -Path $testRoot -Name 'Pester' -Version '4.0.6'
        $info = Get-ChildItem -Path $testRoot -Filter 'Pester.psd1' -Recurse
        $manifest = Test-ModuleManifest -Path $info.FullName
        Start-Sleep -Milliseconds 333
        Install-WhiskeyPowerShellModule -Path $testRoot -Name 'Pester' -Version '4.0.7'
        $newInfo = Get-ChildItem -Path $testRoot -Filter 'Pester.psd1' -Recurse
        $newManifest = Test-ModuleManifest -Path $newInfo.FullName
        $newManifest.Version | Should -Be $manifest.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module directory exists but is empty' {
    AfterEach { Reset }
    It 'should still install the module' {
        Init
        $moduleRootDir = Join-Path -Path $testRoot -ChildPath ('{0}\Pester' -f $powerShellModulesDirectoryName)
        New-Item -Path $moduleRootDir -ItemType Directory | Write-Debug
        Invoke-PowershellInstall -ForModule 'Pester' -Version '4.4.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is missing files' {
    AfterEach { Reset }
    It 'should do something' {
        Init
        Install-WhiskeyPowerShellModule -Path $testRoot -Name 'Pester' -Version '4.4.0'
        $moduleManifest = Join-Path -Path $testRoot -ChildPath ('{0}\Pester\4.4.0\Pester.psd1' -f $powerShellModulesDirectoryName) -Resolve
        Remove-Item -Path $moduleManifest -Force
        Invoke-PowershellInstall -ForModule 'Pester' -Version '4.4.0'
    }
}
