
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$allZipVersions = Find-Module -Name 'Zip' -AllVersions
$latestZip = $allZipVersions | Select-Object -First 1
$result = $null
$expectedModuleName = $null
$expectedModuleVersion = $null

$installedModules = @()

function GivenModule
{
    param(
        [Parameter(Mandatory)]
        [String]$Named,

        [Parameter(Mandatory)]
        [Version]$AtVersion,

        [Parameter(Mandatory)]
        [String]$InstalledIn
    )

    $script:installedModules += [pscustomobject]@{
        'Name' = $Named;
        'Version' = $AtVersion;
        'Path' = (Join-Path -Path $InstalledIn -ChildPath "$($Named).psm1")
    }
}

function Init
{
    param(
    )

    $Global:Error.Clear()

    $script:expectedModuleName = $null
    $script:expectedModuleVersion = $null
    $script:result = $null
    $script:testRoot = New-WhiskeyTestRoot
    $script:installedModules = @()

    Initialize-WhiskeyTestPSModule -BuildRoot $testRoot

    Reset-WhiskeyPSModulePath
    Unregister-WhiskeyPSModulesPath
}

# Wrap private function so we can call it like it's public.
function Install-PowerShellModule
{
    [CmdletBinding()]
    param(
        $Name,
        $Version,
        [switch]$SkipImport,
        $Path
    )

    $parameter = $PSBoundParameters
    $parameter['BuildRoot'] = $testRoot

    Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyPowerShellModule' -Parameter $PSBoundParameters -ErrorAction $ErrorActionPreference
}

function Reset
{
    Reset-WhiskeyTestPSModule
    Reset-WhiskeyPSModulePath
    Register-WhiskeyPSModulesPath
}

function ThenModuleImported
{
    param(
        [String]$AtVersion = $expectedModuleVersion,
        [String]$From
    )

    $module = Get-Module -Name $expectedModuleName
    $module | Should -Not -BeNullOrEmpty
    $module.Version | Should -Be $AtVersion
}

function ThenModuleInstalled
{
    param(
        $Name = $expectedModuleName,
        $AtVersion = $expectedModuleVersion,
        $In = $TestPSModulesDirectoryName
    )
    
    $result | Should -Not -BeNullOrEmpty
    $path = $result.Path
    $errors = @()
    $module = Start-Job {
        Import-Module -Name $using:path -RequiredVersion $using:AtVersion -PassThru -WarningAction Ignore
    } | Wait-Job | Receive-Job -ErrorVariable 'errors'
    $errors | Should -BeNullOrEmpty
    $module | Should -Not -BeNullOrEmpty
    $module.Version | Should -Be $AtVersion

    Join-Path -Path $testRoot -ChildPath "$($In)\$($Name)\$($AtVersion)" | 
        Should -Exist
}

function ThenModuleInfoReturned
{
    param(
        [String]$AtVersion = $script:expectedModuleVersion
    )

    $result | Should -Not -BeNullOrEmpty
    $result | Should -HaveCount 1
    $result | Should -BeOfType ([Management.Automation.PSModuleInfo])
    $result.Name | Should -Be $expectedModuleName
    $result.Version | Should -Be $AtVersion
}

function ThenModuleNotImported
{
    Get-Module -Name $expectedModuleName | Should -BeNullOrEmpty
}

function ThenModuleNotInstalled
{
    param(
        [String]$Named = $expectedModuleName,
        [String]$In
    )

    $rootPath = Join-Path -Path $testRoot -ChildPath $In
    Join-Path -Path $rootPath -ChildPath $Named | Should -Not -Exist
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenNoModuleInfoReturned
{
    $result | Should -BeNullOrEmpty
}

function WhenInstallingPSModule
{
    [CmdletBinding()]
    param(
        $ForModule,
        $Version,
        [switch]$SkipImport,
        [String]$AtPath
    )

    $script:expectedModuleName = $ForModule

    $script:expectedModuleVersion = $Version

    $Global:Error.Clear()

    if( Get-Module -Name $ForModule )
    {
        Remove-Module -Name $ForModule -Force -ErrorAction Ignore
    }

    $installedModules = $script:installedModules
    $global:getWhiskeyPSModuleCalled = $false
    if( $installedModules )
    {
        Mock -CommandName 'Get-WhiskeyPSModule' `
             -ModuleName 'Whiskey' `
             -ParameterFilter {
                 if( $getWhiskeyPSModuleCalled )
                {
                    return $false
                }
                
                $whiskeyCallers = Get-PSCallStack | Where-Object 'Command' -like '*-Whiskey*'
                $whiskeyCallers | Format-Table | Out-String | Write-Debug
                $whiskeyCaller = $whiskeyCallers | Select-Object -First 1 
                $whiskeyCaller | Format-List | Out-String | Write-Debug
                $whiskeyCaller.InvocationInfo | Format-List | Out-String | Write-Debug
                $whiskeyCaller.Arguments | Format-List | Out-String | Write-Debug
                $calledByWhiskey = $whiskeyCaller.Command -eq 'Install-WhiskeyPowerShellModule'
                if( $calledByWhiskey -and -not $getWhiskeyPSModuleCalled )
                {
                    $global:getWhiskeyPSModuleCalled = $true
                }
                return $calledByWhiskey
             }.GetNewClosure() `
             -MockWith { $installedModules | Write-Output }.GetNewClosure()
    }

    $conditionalParams = @{}

    if( $AtPath )
    {
        $conditionalParams['Path'] = $AtPath
    }

    if( $SkipImport )
    {
        $conditionalParams['SkipImport'] = $true
    }

    Push-Location $testRoot
    try
    {
        $script:result = Install-PowerShellModule -Name $ForModule -Version $Version @conditionalParams
    }
    finally
    {
        Remove-Variable -Name 'getWhiskeyPSModuleCalled' -Force -Scope 'Global'
        Pop-Location
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing and re-installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install package management modules and the module' {
        Init
        WhenInstallingPSModule 'Zip' -Version '0.2.0'
        ThenModuleInfoReturned
        ThenModuleInstalled
        ThenModuleImported
        ThenNoErrors

        # Now, make sure the module doesn't get re-installed.
        Mock -CommandName 'Save-Module' -ModuleName 'Whiskey'
        WhenInstallingPSModule 'Zip' -Version '0.2.0'
        Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -Times 0
        ThenNoErrors
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and omitting patch number' {
    AfterEach { Reset }
    It 'should install at patch number 0' {
        Init
        WhenInstallingPSModule 'Zip' -Version '0.2'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion '0.2.0'
        ThenModuleInstalled -AtVersion '0.2.0'
        ThenModuleImported -AtVersion '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing the latest version of a PowerShell module' {
    AfterEach { Reset }
    It 'should install the latest version' {
        Init
        WhenInstallingPSModule 'Zip'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when reinstalling the latest version of a PowerShell module in the current directory' {
    AfterEach { Reset }
    It 'should install the latest version' {
        Init
        WhenInstallingPSModule 'Zip' -AtPath '.'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version -From '.'
        ThenModuleInstalled -AtVersion $latestZip.Version -In '.'

        # Re-install
        WhenInstallingPSModule 'Zip' -AtPath '.'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version -From '.'
        ThenModuleInstalled -AtVersion $latestZip.Version -In '.'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module using wildcard version' {
    AfterEach { Reset }
    It 'should resolve to the latest version that matches the wildcard' {
        Init
        WhenInstallingPSModule 'Zip' -Version "$(([version]$latestZip.Version).Major).*"
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module' {
    AfterEach { Reset }
    It 'should install the module' {
        Init
        WhenInstallingPSModule 'Zip' -Version '0.2.0'
        ThenModuleInfoReturned
        ThenModuleInstalled
        ThenModuleImported
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and the version doesn''t exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $InformationPreference = 'Continue'
        $result = Install-PowerShellModule -Name 'Zip' -Version '0.0.1' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and version parameter is empty' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $result = Install-PowerShellModule -Name 'Fubar' -Version '' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is already installed' {
    AfterEach { Reset }
    It 'should install the new version' {
        Init
        Install-PowerShellModule -Name 'Zip' -Version $latestZip.Version
        $info = Get-ChildItem -Path $testRoot -Filter 'Zip.psd1' -Recurse
        $manifest = Test-ModuleManifest -Path $info.FullName
        Start-Sleep -Milliseconds 333
        Install-PowerShellModule -Name 'Zip' -Version $latestZip.Version
        $newInfo = Get-ChildItem -Path $testRoot -Filter 'Zip.psd1' -Recurse
        $newManifest = Test-ModuleManifest -Path $newInfo.FullName
        $newManifest.Version | Should -Be $manifest.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module directory exists but is empty' {
    AfterEach { Reset }
    It 'should still install the module' {
        Init
        $moduleRootDir = Join-Path -Path $testRoot -ChildPath "$($TestPSModulesDirectoryName)\Zip"
        New-Item -Path $moduleRootDir -ItemType Directory | Write-WhiskeyDebug
        WhenInstallingPSModule -ForModule 'Zip' -Version $latestZip.Version
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module can''t be imported' {
    AfterEach { Reset }
    It 'should re-download the module' {
        Init
        Install-PowerShellModule -Name 'Zip' -Version $latestZip.Version
        $moduleManifest = Join-Path -Path $testRoot -ChildPath ('{0}\Zip\{1}\Zip.psd1' -f $TestPSModulesDirectoryName,$latestZip.Version) -Resolve
        '@{ }' | Set-Content -Path $moduleManifest
        { Test-ModuleManifest -Path $moduleManifest -ErrorAction Ignore } | Should -Throw
        $Global:Error.Clear()
        WhenInstallingPSModule -ForModule 'Zip' -Version $latestZip.Version
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when skipping import' {
    AfterEach { Reset }
    It 'should not import the module' {
        Init
        WhenInstallingPSModule 'Zip' -SkipImport
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
        ThenModuleNotImported -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when previous version installed and user wants latest version by leaving version empty' {
    AfterEach { Reset }
    It 'should install the latest version' {
        Init
        WhenInstallingPSModule 'Zip' -Version '0.1.*'
        ThenModuleInfoReturned -AtVersion '0.1.0'
        ThenModuleInstalled -AtVersion '0.1.0'
        ThenModuleImported -AtVersion '0.1.0'

        WhenInstallingPSModule 'Zip'
        ThenModuleInfoReturned -AtVersion $latestZip.Version
        ThenModuleInstalled -AtVersion $latestZip.Version
        ThenModuleImported -AtVersion $latestZip.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when multiple modules already installed that match task wildcard' {
    AfterEach { Reset }
    It 'should return latest version' {
        Init
        $newestVersion = $allZipVersions | Select-Object -First 1
        $previousVersion = $allZipVersions | Select-Object -Skip 1 | Select-Object -First 1
        WhenInstallingPSModule 'Zip' -Version $newestVersion.Version
        ThenModuleInstalled 'Zip' -AtVersion $newestVersion.Version
        WhenInstallingPSModule 'Zip' -Version $previousVersion.Version
        ThenModuleInstalled 'Zip' -AtVersion $previousVersion.Version
        Mock -CommandName 'Save-Module' -ModuleName 'Whiskey'
        WhenInstallingPSModule 'Zip' -Version '*'
        Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -Times 0
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $newestVersion.Version
    }
}

Describe "Install-WhiskeyPowerShellModule.when user installing to custom path but module exists globally" {
    AfterEach { Reset }
    It 'should install module at the custom path' {
        Init
        $globalModulePath = 
            ($env:PSModulePath -split [IO.Path]::PathSeparator) |
            Where-Object { $_ -match '\b(Windows)?PowerShell\b' } |
            Select-Object -First 1
        Write-Verbose $globalModulePath -Verbose
        GivenModule 'Zip' -AtVersion $latestZip.Version -InstalledIn $globalModulePath
        WhenInstallingPSModule 'Zip' -Version $latestZip.Version -AtPath 'mycustompath'
        ThenModuleInfoReturned 'Zip' -AtVersion $latestZip.Version
        ThenModuleInstalled 'Zip' -AtVersion $latestZip.Version -In 'mycustompath'
        ThenModuleImported 'Zip' -AtVersion $latestZip.Version -From 'mycustompath'
        ThenModuleNotInstalled 'Zip' -In 'PSModules'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when module fails to install' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        Mock -CommandName 'Save-Module' -ModuleName 'Whiskey'
        { WhenInstallingPSModule 'Zip' -ErrorAction Stop } |
            Should -Throw 'the module doesn''t exist after running'
        ThenNoModuleInfoReturned
        ThenModuleNotInstalled
        ThenModuleNotImported
    }
}

Describe 'Install-WhiskeyPowerShellModule.when remains of old module still in place and can''t be removed' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $expectedVersion = $latestZip.Version
        $expectedPathWildcard = "*\PSModules\Zip\$($expectedVersion)\*"
        $parameterFilter = [scriptblock]::Create("{ `$Path -like ""$($expectedPathWildcard)""}")
        Mock -Command 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter $parameterFilter -MockWith { return $true }
        Mock -Command 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter $parameterFilter
        New-Item -Path (Join-Path -Path $testRoot -ChildPath "PSModules\Zip\$($latestZip.Version)") -ItemType 'Directory'
        $slash = [IO.Path]::DirectorySeparatorChar
        $expectedMsg ="the destination path "".$($slash)PSModules$($slash)Zip$($slash)$($expectedVersion)"" exists" 
        { WhenInstallingPSModule 'Zip' -ErrorAction Stop } | Should -Throw $expectedMsg
        ThenNoModuleInfoReturned
        ThenModuleNotInstalled
        ThenModuleNotImported
    }
}