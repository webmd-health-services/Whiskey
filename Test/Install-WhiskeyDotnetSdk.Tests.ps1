
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyDotNetSdk.ps1' -Resolve)

$dotNetPath = $null
$originalPath = $env:Path
$globalDotNetDirectory = $null
$localDotNetDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:dotNetPath = $null
    $script:globalDotNetDirectory = Join-Path $TestDrive.FullName -ChildPath 'GlobalDotNetSDK'
    $script:localDotNetDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.dotnet'
}

function GivenGlobalDotNet
{
    param(
        $Version
    )

    $dotNetExePath = Join-Path -Path $globalDotNetDirectory -ChildPath 'dotnet.exe'
    New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

    $dotNetSdkPath = Join-Path -Path $globalDotNetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
    New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null

    $env:Path += (';{0}' -f $globalDotNetDirectory)
}

function MockDotNetInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotNetInstallScript -like '*\dotnet-install.ps1' } -MockWith {
        $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath 'dotnet.exe'
        New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

        $dotNetSdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
        New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null
    }
}

function MockFailedDotNetInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotNetInstallScript -like '*\dotnet-install.ps1' }
}

function MockFailedSdkVersionInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotNetInstallScript -like '*\dotnet-install.ps1' } -MockWith {
        $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath 'dotnet.exe'
        New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

        $sdkWithoutVersionPath = Join-Path -Path $InstallRoot -ChildPath 'sdk'
        New-Item -Path $sdkWithoutVersionPath -ItemType Directory -Force | Out-Null
    }
}

function Remove-DotNetInstallsFromPath
{
    $dotNetInstalls = Get-Command -Name 'dotnet.exe' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
    foreach ($path in $dotNetInstalls)
    {
        $dotNetDirectory = [regex]::Escape(($path | Split-Path -Parent))
        $dotNetDirectory = ('{0}\\?' -f $dotNetDirectory)
        $env:Path = $env:Path -replace $dotNetDirectory,''
    }
}

function Restore-OriginalPathEnvironment
{
    $env:Path = $originalPath
}

function ThenErrorIs
{
    param(
        $Message
    )

    It 'should write an error' {
        $Global:Error | Should -Match $Message
    }
}

function ThenInstalledDotNet
{
    param(
        $ExpectedVersion
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $ExpectedVersion)

    It ('.NET Core SDK version ''{0}'' should be installed' -f $ExpectedVersion) {
        $sdkPath | Should -Exist
        Get-ChildItem $sdkPath | Should -Not -BeNullOrEmpty
    }
}

function ThenNotInstalledDotNet
{
    param(
        $Version
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $Version)

    It ('.NET Core SDK version ''{0}'' should not be installed' -f $Version) {
        $sdkPath | Should -Not -Exist
    }
}

function ThenReturnedPathToDotNet
{
    param(
        [switch]
        $Global
    )

    If ($Global)
    {
        It 'should return path to globally installed dotnet.exe' {
            $dotNetPath | Should -Not -BeNullOrEmpty
            $dotNetPath | Should -Exist
            $dotNetPath | Should -Be (Join-Path -Path $globalDotNetDirectory -ChildPath 'dotnet.exe')
        }
    }
    else
    {
        It 'should return path to locally installed dotnet.exe' {
            $dotNetPath | Should -Not -BeNullOrEmpty
            $dotNetPath | Should -Exist
            $dotNetPath | Should -Be (Join-Path -Path $localDotNetDirectory -ChildPath 'dotnet.exe')
        }
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $dotNetPath | Should -BeNullOrEmpty
    }
}

function WhenInstallingDotNet
{
    [CmdletBinding()]
    param(
        $Version,

        [switch]
        $SearchExisting
    )

    $script:dotNetPath = Install-WhiskeyDotNetSdk -InstallRoot $localDotNetDirectory -Version $Version -SearchExisting:$SearchExisting
}

Describe 'Install-WhiskeyDotNetSdk.when installing the SDK version ''1.0.1''' {
    # Leave this test UN-MOCKED so we have at least one test that actually runs dotnet-install.ps1 to ensure it works properly.

    Init
    WhenInstallingDotNet '1.0.1'
    ThenInstalledDotNet '1.0.1'
    ThenReturnedPathToDotNet

    Context 'When installing newer version ''2.1.4'' of the SDK alongside the old one' {
        WhenInstallingDotNet '2.1.4'
        ThenInstalledDotNet '1.0.1'
        ThenInstalledDotNet '2.1.4'
        ThenReturnedPathToDotNet
    }
}

Describe 'Install-WhiskeyDotNetSdk.when installing SDK version ''1.0.1'' which already exists globally but not searching globally' {
    Remove-DotNetInstallsFromPath
    try
    {
        Init
        MockDotNetInstall
        GivenGlobalDotNet '1.0.1'
        WhenInstallingDotNet '1.0.1'
        ThenInstalledDotNet '1.0.1'
        ThenReturnedPathToDotNet
    }
    finally
    {
        Restore-OriginalPathEnvironment
    }
}

Describe 'Install-WhiskeyDotNetSdk.when SDK version ''1.0.1'' already installed globally' {
    Remove-DotNetInstallsFromPath
    try
    {
        Init
        MockDotNetInstall
        GivenGlobalDotNet '1.0.1'
        WhenInstallingDotNet '1.0.1' -SearchExisting
        ThenNotInstalledDotNet '1.0.1'
        ThenReturnedPathToDotNet -Global
    }
    finally
    {
        Restore-OriginalPathEnvironment
    }
}

Describe 'Install-WhiskeyDotNetSdk.when global SDK install exists but not at correct version' {
    Remove-DotNetInstallsFromPath
    try
    {
        Init
        MockDotNetInstall
        GivenGlobalDotNet '1.0.1'
        WhenInstallingDotNet '1.0.4' -SearchExisting
        ThenInstalledDotNet '1.0.4'
        ThenReturnedPathToDotNet
    }
    finally
    {
        Restore-OriginalPathEnvironment
    }
}

Describe 'Install-WhiskeyDotNetSdk.when cannot find dotnet.exe after install' {
    Init
    MockFailedDotNetInstall
    WhenInstallingDotNet '1.0.4' -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorIs '''dotnet.exe''\ was\ not\ found'
}

Describe 'Install-WhiskeyDotNetSdk.when installing SDK but desired SDK version was not found after install' {
    Init
    MockFailedSdkVersionInstall
    WhenInstallingDotNet '1.0.4' -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorIs 'version\ ''1.0.4''\ of\ the\ SDK\ was\ not\ found'
}
