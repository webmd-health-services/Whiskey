
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$latestZip = Find-Module -Name 'Zip' | Select-Object -First 1

function Init
{
    param(
    )

    $script:testRoot = New-WhiskeyTestRoot'

    Initialize-WhiskeyTestPSModule -BuildRoot $testRoot
}

# Wrap private function so we can call it like it's public.
function Install-WhiskeyPowerShellModule
{
    [CmdletBinding()]
    param(
        $Name,
        $Version,
        [Switch]$SkipImport
    )

    $parameter = $PSBoundParameters
    $parameter['BuildRoot'] = $testRoot

    Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyPowerShellModule' -Parameter $PSBoundParameters -ErrorAction $ErrorActionPreference
}

function Invoke-PowershellInstall
{
    param(
        $ForModule,
        $Version,
        $ActualVersion,
        [Switch]$SkipImport
    )

    if( -not $ActualVersion )
    {
        $ActualVersion = $Version
    }

    $Global:Error.Clear()

    if( Get-Module -Name $ForModule )
    {
        Remove-Module -Name $ForModule -Force -ErrorAction Ignore
    }

    $result = Install-WhiskeyPowerShellModule -Name $ForModule -Version $Version -SkipImport:$SkipImport

    $moduleRootPath = Join-Path -Path $testRoot -ChildPath ('{0}\{1}' -f $PSModulesDirectoryName,$ForModule)
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
    Reset-WhiskeyTestPSModule
}
function ThenModuleImported
{
    param(
        $Named,
        $AtVersion
    )

    $module = Get-Module -Name $Named 
    $module | Should -Not -BeNullOrEmpty
    $module.Version | Should -Be $AtVersion
}

function ThenModuleNotImported
{
    param(
        $Named
    )

    Get-Module -Name $Named | Should -BeNullOrEmpty
}

function ThenModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )
    
    Join-Path -Path $testRoot -ChildPath ('{0}\{1}\{2}' -f $PSModulesDirectoryName,$Name,$AtVersion) | Should -Exist
}

Describe 'Install-WhiskeyPowerShellModule.when installing and re-installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install package management modules and the module' {
        Init
        $Global:Error.Clear()

        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        ThenModuleInstalled 'Zip' -AtVersion '0.2.0'
        ThenModuleImported 'Zip' -AtVersion '0.2.0'

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
        ThenModuleImported 'Zip' -AtVersion '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module omitting Version' {
    AfterEach { Reset }
    It 'should install the latest version' {
        Init
        Invoke-PowershellInstall -ForModule 'Zip' -Version '' -ActualVersion $latestZip.Version
        ThenModuleImported 'Zip' -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module using wildcard version' {
    AfterEach { Reset }
    It 'should resolve to the latest version that matches the wildcard' {
        Init
        $version = [version]($latestZip.Version)
        Invoke-PowershellInstall -ForModule 'Zip' -Version ('{0}.*' -f $version.Major) -ActualVersion $latestZip.Version
        ThenModuleImported 'Zip' -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install the module' {
        Init
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        ThenModuleImported 'Zip' -AtVersion '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and the version doesn''t exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Name 'Zip' -Version '0.0.1' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and version parameter is empty' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Name 'Fubar' -Version '' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is already installed' {
    AfterEach { Reset }
    It 'should install the new version' {
        Init
        Install-WhiskeyPowerShellModule -Name 'Zip' -Version $latestZip.Version
        $info = Get-ChildItem -Path $testRoot -Filter 'Zip.psd1' -Recurse
        $manifest = Test-ModuleManifest -Path $info.FullName
        Start-Sleep -Milliseconds 333
        Install-WhiskeyPowerShellModule -Name 'Zip' -Version $latestZip.Version
        $newInfo = Get-ChildItem -Path $testRoot -Filter 'Zip.psd1' -Recurse
        $newManifest = Test-ModuleManifest -Path $newInfo.FullName
        $newManifest.Version | Should -Be $manifest.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module directory exists but is empty' {
    AfterEach { Reset }
    It 'should still install the module' {
        Init
        $moduleRootDir = Join-Path -Path $testRoot -ChildPath ('{0}\Zip' -f $PSModulesDirectoryName)
        New-Item -Path $moduleRootDir -ItemType Directory | Write-Debug
        Invoke-PowershellInstall -ForModule 'Zip' -Version $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is missing files' {
    AfterEach { Reset }
    It 'should do something' {
        Init
        Install-WhiskeyPowerShellModule -Name 'Zip' -Version $latestZip.Version
        $moduleManifest = Join-Path -Path $testRoot -ChildPath ('{0}\Zip\{1}\Zip.psd1' -f $PSModulesDirectoryName,$latestZip.Version) -Resolve
        Remove-Item -Path $moduleManifest -Force
        Invoke-PowershellInstall -ForModule 'Zip' -Version $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when skipping import' {
    AfterEach { Reset }
    It 'should not  import the module' {
        Init
        Install-WhiskeyPowerShellModule 'Zip' -SkipImport
        ThenModuleNotImported 'Zip'
    }
}