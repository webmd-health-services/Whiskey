
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dotNetPath = $null
$originalPath = $env:PATH
$globalDotNetDirectory = $null
$localDotNetDirectory = $null
$dotnetExeName = 'dotnet'
if( $IsWindows )
{
    $dotnetExeName = 'dotnet.exe'
}

$tempDotNetPath = $null
if( $IsLinux )
{
    # On the build server, dotnet and curl are in the same directory. Some tests remove the path 
    # in which dotnet is installed to test that it gets downloaded and installed. Since curl is
    # at the same path, the download fail because dotnet-install.sh can't find curl. So, we
    # have to set aside the global dotnet if it exists in the same directory as curl.
    $sysDotNetPath = Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty 'Source' 
    $dotnetDir = $sysDotNetPath | Split-Path -Parent
    $curlDir = Get-Command -Name 'curl' -Erroraction SilentlyContinue | Select-Object -ExpandProperty 'Source' | Split-Path -Parent
    if( $curlDir -eq $dotnetDir )
    {
        $tempDotNetName = 'dotnet{0}' -f [IO.Path]::GetRandomFileName()
        $tempDotNetPath = Join-Path -Path $dotnetDir -ChildPath $tempDotNetName
        sudo mv $sysDotNetPath $tempDotNetPath
    }
}

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

    $dotNetExePath = Join-Path -Path $globalDotNetDirectory -ChildPath $dotnetExeName
    New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

    $dotNetSdkPath = Join-Path -Path $globalDotNetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
    New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null

    $env:PATH = ('{0}{1}{2}' -f $globalDotNetDirectory,[IO.Path]::PathSeparator,$env:PATH)
}

function GivenDotNetSuccessfullyInstalls
{
    Mock -CommandName 'Invoke-Command' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $dotNetInstallScript -like '*\dotnet-install.ps1' } `
         -MockWith {
            $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath $dotnetExeName
            New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

            $dotNetSdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
            New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null
        }
}

function GivenDotNetCommandFailsToInstall
{
    Mock -CommandName 'Invoke-Command' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $dotNetInstallScript -like '*[/\]dotnet-install.*' }
}

function GivenDotNetSdkFailsToInstall
{
    Mock -CommandName 'Invoke-Command' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $dotNetInstallScript -like '*[/\]dotnet-install.*' } `
         -MockWith {
            $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath $dotnetExeName
            New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

            $sdkWithoutVersionPath = Join-Path -Path $InstallRoot -ChildPath 'sdk'
            New-Item -Path $sdkWithoutVersionPath -ItemType Directory -Force | Out-Null
        }
}

function GivenDotNetNotInstalled
{
    $dotNetInstalls = Get-Command -Name $dotnetExeName -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
    foreach ($path in $dotNetInstalls)
    {
        $dotNetDirectory = [regex]::Escape(($path | Split-Path -Parent))
        $dotNetDirectory = ('{0}{1}?' -f $dotNetDirectory,[regex]::Escape([IO.Path]::DirectorySeparatorChar))
        $env:PATH = $env:PATH -replace $dotNetDirectory,''
    }
}

function ThenRestoreOriginalPathEnvironment
{
    $env:PATH = $originalPath
}

function ThenErrorIs
{
    param(
        $Message
    )

    $Global:Error | Should -Match $Message
}

function ThenInstalledDotNet
{
    param(
        $ExpectedVersion
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $ExpectedVersion)

    $sdkPath | Should -Exist
    Get-ChildItem $sdkPath | Should -Not -BeNullOrEmpty
}

function ThenNotInstalledDotNet
{
    param(
        $Version
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $Version)

    $sdkPath | Should -Not -Exist
}

function ThenReturnedPathToDotNet
{
    param(
        [switch]
        $Global
    )

    If ($Global)
    {
        $dotNetPath | Should -Not -BeNullOrEmpty
        $dotNetPath | Should -Exist
        $dotNetPath | Should -Be (Join-Path -Path $globalDotNetDirectory -ChildPath $dotnetExeName)
    }
    else
    {
        $dotNetPath | Should -Not -BeNullOrEmpty
        $dotNetPath | Should -Exist
        $dotNetPath | Should -Be (Join-Path -Path $localDotNetDirectory -ChildPath $dotnetExeName)
    }
}

function ThenReturnedNothing
{
    $dotNetPath | Should -BeNullOrEmpty
}

function WhenInstallingDotNet
{
    [CmdletBinding()]
    param(
        $Version,

        [switch]
        $Global
    )

    $parameter = $PSBoundParameters
    $parameter['InstallRoot'] = $localDotNetDirectory;
    $script:dotNetPath = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyDotNetSdk' -Parameter $parameter
}

Describe 'Install-WhiskeyDotNetSdk.when installing the SDK version "2.0.3"' {
    It 'should install 2.0.3' {
        # Leave this test UN-MOCKED so we have at least one test that actually runs dotnet-install.* to ensure it works properly.

        Init
        WhenInstallingDotNet '2.0.3'
        ThenInstalledDotNet '2.0.3'
        ThenReturnedPathToDotNet
    }

    Context 'When installing newer version "2.1.4" of the SDK alongside the old one' {
        It 'should upgrade existing version' {
            WhenInstallingDotNet '2.1.4'
            ThenInstalledDotNet '2.0.3'
            ThenInstalledDotNet '2.1.4'
            ThenReturnedPathToDotNet
        }
    }
}

Describe 'Install-WhiskeyDotNetSdk.when cannot find dotnet executable after install' {
    It 'should fail' {
        Init
        GivenDotNetCommandFailsToInstall
        WhenInstallingDotNet '1.1.11' -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorIs ('"{0}"\ executable\ was\ not\ found' -f [regex]::Escape($dotnetExeName))
    }
}

Describe 'Install-WhiskeyDotNetSdk.when installing SDK but desired SDK version was not found after install' {
    It 'should fail' {
        Init
        GivenDotNetSdkFailsToInstall
        WhenInstallingDotNet '1.0.4' -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorIs 'version\ "1.0.4"\ of\ the\ SDK\ was\ not\ found'
    }
}

try
{
    GivenDotNetNotInstalled

    Describe 'Install-WhiskeyDotNetSdk.when searching globally and SDK not installed anywhere' {
        It 'should install locally' {
            Init
            GivenDotNetSuccessfullyInstalls
            WhenInstallingDotNet '2.1.4' -Global
            ThenInstalledDotNet '2.1.4'
            ThenReturnedPathToDotNet
        }
    }

    Describe 'Install-WhiskeyDotNetSdk.when installing SDK version which already exists globally but not searching globally' {
        It 'should install' {
            Init
            GivenDotNetSuccessfullyInstalls
            GivenGlobalDotNet '1.1.11'
            WhenInstallingDotNet '1.1.11'
            ThenInstalledDotNet '1.1.11'
            ThenReturnedPathToDotNet
        }
    }

    Describe 'Install-WhiskeyDotNetSdk.when SDK version already installed globally' {
        It 'should not install locally' {
            Init
            GivenDotNetSuccessfullyInstalls
            GivenGlobalDotNet '1.1.11'
            WhenInstallingDotNet '1.1.11' -Global
            ThenNotInstalledDotNet '1.1.11'
            ThenReturnedPathToDotNet -Global
        }
    }

    Describe 'Install-WhiskeyDotNetSdk.when global SDK install exists but not at correct version' {
        It 'should install correct version locally' {
            Init
            GivenDotNetSuccessfullyInstalls
            GivenGlobalDotNet '2.1.4'
            WhenInstallingDotNet '1.1.11' -Global
            ThenInstalledDotNet '1.1.11'
            ThenReturnedPathToDotNet
        }
    }
}
finally
{
    ThenRestoreOriginalPathEnvironment
}

if( $tempDotNetPath )
{
    sudo mv $tempDotNetPath $sysDotNetPath
}
