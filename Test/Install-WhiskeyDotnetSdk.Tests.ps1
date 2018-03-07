
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyDotnetSdk.ps1' -Resolve)

$dotnetPath = $null
$globalDotnetDirectory = $null
$localDotnetDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:dotnetPath = $null
    $script:globalDotnetDirectory = Join-Path $TestDrive.FullName -ChildPath 'GlobalDotnetSDK'
    $script:localDotnetDirectory = Join-Path -Path $TestDrive.FullName -ChildPath '.dotnet'

    Remove-DotnetInstallsFromPath
}

function GivenGlobalDotnet
{
    param(
        $Version
    )

    $dotnetExePath = Join-Path -Path $globalDotnetDirectory -ChildPath 'dotnet.exe'
    New-Item -Path $dotnetExePath -ItemType File -Force | Out-Null

    $dotnetSdkPath = Join-Path -Path $globalDotnetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
    New-Item -Path $dotnetSdkPath -ItemType File -Force | Out-Null

    $env:Path += (';{0}' -f $globalDotnetDirectory)
}

function MockDotnetInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotnetInstallScript -like '*\dotnet-install.ps1' } -MockWith {
        $dotnetExePath = Join-Path -Path $InstallRoot -ChildPath 'dotnet.exe'
        New-Item -Path $dotnetExePath -ItemType File -Force | Out-Null

        $dotnetSdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
        New-Item -Path $dotnetSdkPath -ItemType File -Force | Out-Null
    }
}

function MockFailedDotnetInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotnetInstallScript -like '*\dotnet-install.ps1' }
}

function MockFailedSdkVersionInstall
{
    Mock -CommandName 'Invoke-Command' -ParameterFilter { $dotnetInstallScript -like '*\dotnet-install.ps1' } -MockWith {
        $dotnetExePath = Join-Path -Path $InstallRoot -ChildPath 'dotnet.exe'
        New-Item -Path $dotnetExePath -ItemType File -Force | Out-Null

        $sdkWithoutVersionPath = Join-Path -Path $InstallRoot -ChildPath 'sdk'
        New-Item -Path $sdkWithoutVersionPath -ItemType Directory -Force | Out-Null
    }
}

function Remove-DotnetInstallsFromPath
{
    $dotnetInstalls = Get-Command -Name 'dotnet.exe' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
    foreach ($path in $dotnetInstalls)
    {
        $dotnetDirectory = [regex]::Escape(($path | Split-Path -Parent))
        $dotnetDirectory = ('{0}\\?' -f $dotnetDirectory)
        $env:Path = $env:Path -replace $dotnetDirectory,''
    }
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

function ThenInstalledDotnet
{
    param(
        $ExpectedVersion
    )

    $sdkPath = Join-Path -Path $localDotnetDirectory -ChildPath ('sdk\{0}' -f $ExpectedVersion)

    It ('.NET Core SDK version ''{0}'' should be installed' -f $ExpectedVersion) {
        $sdkPath | Should -Exist
        Get-ChildItem $sdkPath | Should -Not -BeNullOrEmpty
    }
}

function ThenNotInstalledDotnet
{
    param(
        $Version
    )

    $sdkPath = Join-Path -Path $localDotnetDirectory -ChildPath ('sdk\{0}' -f $Version)

    It ('.NET Core SDK version ''{0}'' should not be installed' -f $Version) {
        $sdkPath | Should -Not -Exist
    }
}

function ThenReturnedPathToDotnet
{
    param(
        [switch]
        $Global
    )

    If ($Global)
    {
        It 'should return path to globally installed dotnet.exe' {
            $dotnetPath | Should -Not -BeNullOrEmpty
            $dotnetPath | Should -Exist
            $dotnetPath | Should -Be (Join-Path -Path $globalDotnetDirectory -ChildPath 'dotnet.exe')
        }
    }
    else
    {
        It 'should return path to locally installed dotnet.exe' {
            $dotnetPath | Should -Not -BeNullOrEmpty
            $dotnetPath | Should -Exist
            $dotnetPath | Should -Be (Join-Path -Path $localDotnetDirectory -ChildPath 'dotnet.exe')
        }
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $dotnetPath | Should -BeNullOrEmpty
    }
}

function WhenInstallingDotnet
{
    [CmdletBinding()]
    param(
        $Version,

        [switch]
        $SearchExisting
    )

    $script:dotnetPath = Install-WhiskeyDotnetSdk -InstallRoot $localDotnetDirectory -Version $Version -SearchExisting:$SearchExisting
}

Describe 'Install-WhiskeyDotnetSdk.when installing the SDK version ''1.0.1''' {
    # Leave this test UN-MOCKED so we have at least one test that actually runs dotnet-install.ps1 to ensure it works properly.

    Init
    WhenInstallingDotnet '1.0.1'
    ThenInstalledDotnet '1.0.1'
    ThenReturnedPathToDotnet

    Context 'When installing newer version ''2.1.4'' of the SDK alongside the old one' {
        WhenInstallingDotnet '2.1.4'
        ThenInstalledDotnet '1.0.1'
        ThenInstalledDotnet '2.1.4'
        ThenReturnedPathToDotnet
    }
}

Describe 'Install-WhiskeyDotnetSdk.when installing SDK version ''1.0.1'' which already exists globally but not searching globally' {
    Init
    MockDotnetInstall
    GivenGlobalDotnet '1.0.1'
    WhenInstallingDotnet '1.0.1'
    ThenInstalledDotnet '1.0.1'
    ThenReturnedPathToDotnet
}

Describe 'Install-WhiskeyDotnetSdk.when SDK version ''1.0.1'' already installed globally' {
    Init
    MockDotnetInstall
    GivenGlobalDotnet '1.0.1'
    WhenInstallingDotnet '1.0.1' -SearchExisting
    ThenNotInstalledDotnet '1.0.1'
    ThenReturnedPathToDotnet -Global
}

Describe 'Install-WhiskeyDotnetSdk.when global SDK install exists but not at correct version' {
    Init
    MockDotnetInstall
    GivenGlobalDotnet '1.0.1'
    WhenInstallingDotnet '1.0.4' -SearchExisting
    ThenInstalledDotnet '1.0.4'
    ThenReturnedPathToDotnet
}

Describe 'Install-WhiskeyDotnetSdk.when cannot find dotnet.exe after install' {
    Init
    MockFailedDotnetInstall
    WhenInstallingDotnet '1.0.4' -SearchExisting -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorIs '''dotnet.exe''\ was\ not\ found'
}

Describe 'Install-WhiskeyDotnetSdk.when installing SDK but desired SDK version was not found after install' {
    Init
    MockFailedSdkVersionInstall
    WhenInstallingDotnet '1.0.4' -SearchExisting -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorIs 'version\ ''1.0.4''\ of\ the\ SDK\ was\ not\ found'
}
