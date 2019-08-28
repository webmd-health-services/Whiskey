
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyDotNetTool.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotNetSdkVersion.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyDotNetSdk.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Set-WhiskeyDotNetGlobalJson.ps1')

$dotnetPath = $null
$globalDotNetDirectory = $null
$originalPath = $env:PATH
$version = $null
$workingDirectory = $null

$dotnetExeName = 'dotnet'
if( $IsWindows )
{
    $dotnetExeName = 'dotnet.exe'
}

function Init
{
    $script:dotnetPath = $null
    $script:globalDotNetDirectory = Join-Path -Path $TestDrive.FullName -ChildPath 'GlobalDotNetSDK'
    $script:version = $null
    $script:workingDirectory = $null
}

function Get-DotNetLatestLtsVersion
{
    Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' | Where-Object { $_ -match '(\d+\.\d+\.\d+)'} | Out-Null
    return $Matches[1]
}

function GivenGlobalDotNetInstalled
{
    param(
        $Version
    )

    New-Item -Path (Join-Path -Path $globalDotNetDirectory -ChildPath $dotnetExeName) -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path -Path $globalDotNetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)) -ItemType File -Force | Out-Null
    $env:PATH += ('{0}{1}' -f [IO.Path]::PathSeparator,$globalDotNetDirectory)
}

function GivenBadGlobalJson
{
    @'
{
    "sdk": "version",

'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'global.json') -Force
}
function GivenGlobalJsonSdkVersion
{
    param(
        $Version,
        $Directory = $TestDrive.FullName
    )

    @{
        'sdk' = @{
            'version' = $Version
        }
    } | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path -Path $Directory -Child 'global.json') -Force
}

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function GivenWorkingDirectory
{
    param(
        $Directory
    )

    $script:workingDirectory = Join-Path -Path $TestDrive.FullName -ChildPath $Directory
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
}

function GivenDotNetSuccessfullyInstalls
{
    Mock -CommandName 'Install-WhiskeyDotNetSdk' -MockWith {
        $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath $dotnetExeName
        New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

        $dotNetSdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
        New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null

        return $dotNetExePath
    }
}

function GivenDotNetNotInstalled
{
    $dotNetInstalls = Get-Command -Name $dotnetExeName -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
    foreach ($path in $dotNetInstalls)
    {
        $dotNetDirectory = [regex]::Escape(($path | Split-Path -Parent))
        $dotNetDirectory = ('{0}\\?' -f $dotNetDirectory)
        $env:PATH = $env:PATH -replace $dotNetDirectory,''
    }
}

function ThenRestoreOriginalPathEnvironment
{
    $env:PATH = $originalPath
}

function ThenDotNetLocallyInstalled
{
    param(
        $Version
    )

    $dotNetSdkPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.dotnet\sdk\{0}' -f $Version)
    It 'should install .NET Core SDK locally' {
        $dotNetSdkPath | Should -Exist
    }
}

function ThenDotNetNotLocallyInstalled
{
    param(
        $Version
    )

    $dotNetSdkPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.dotnet\sdk\{0}' -f $Version)
    It 'should not install .NET Core SDK locally' {
        $dotNetSdkPath | Should -Not -Exist
    }
}

function ThenDotNetSdkVersion
{
    param(
        [string]
        $Version
    )

    Push-Location -Path $workingDirectory
    try
    {
        It 'should install correct .NET Core SDK version' {
            & $dotnetPath --version | Should -Be $Version
        }
    }
    finally
    {
        Pop-Location
    }
}

function ThenError
{
    param(
        $Message
    )

    It 'should write an error message' {
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenGlobalJsonVersion
{
    param(
        $Version,
        $Directory = $TestDrive.FullName
    )

    $globalJsonVersion = Get-Content -Path (Join-Path -Path $Directory -ChildPath 'global.json') -Raw |
                            ConvertFrom-Json |
                            Select-Object -ExpandProperty 'sdk' -ErrorAction Ignore |
                            Select-Object -ExpandProperty 'version' -ErrorAction Ignore

    It ('should update global.json sdk version to ''{0}''' -f $Version) {
        $globalJsonVersion | Should -Be $Version
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $dotnetPath | Should -BeNullOrEmpty
    }
}

function ThenReturnedValidDotNetPath
{
    It 'should return valid path to dotnet executable' {
        $dotnetPath | Should -Exist
    }
}

function WhenInstallingDotNetTool
{
    [CmdletBinding()]
    param()

    $Global:Error.Clear()

    if (-not $workingDirectory)
    {
        $script:workingDirectory = $TestDrive.FullName
    }

    $script:dotnetPath = Install-WhiskeyDotNetTool -InstallRoot $TestDrive.FullName -WorkingDirectory $workingDirectory -Version $version
}

Describe 'Install-WhiskeyDotNetTool.when installing specific version' {
    Init
    GivenVersion '2.1.505'
    GivenGlobalJsonSdkVersion '2.1.300'
    WhenInstallingDotNetTool
    ThenReturnedValidDotNetPath
    ThenGlobalJsonVersion '2.1.505'
    ThenDotNetSdkVersion '2.1.505'
}

Describe 'Install-WhiskeyDotNetTool.when installing newer version' {
    Init
    GivenVersion '2.1.300'
    WhenInstallingDotNetTool

    GivenVersion '2.1.505'
    WhenInstallingDotNetTool
    ThenReturnedValidDotNetPath
    ThenGlobalJsonVersion '2.1.505'
    ThenDotNetSdkVersion '2.1.505'
}

Describe 'Install-WhiskeyDotNetTool.when given wildcard version' {
    Init
    GivenVersion '2.*'
    WhenInstallingDotNetTool
    ThenReturnedValidDotNetPath
    ThenGlobalJsonVersion (Resolve-WhiskeyDotNetSdkVersion -Version '2.*')
    ThenDotNetSdkVersion (Resolve-WhiskeyDotNetSdkVersion -Version '2.*')
}

Describe 'Install-WhiskeyDotNetTool.when existing global.json contains invalid JSON' {
    Init
    GivenBadGlobalJson
    WhenInstallingDotNetTool -ErrorAction SilentlyContinue
    ThenError '\bcontains\ invalid\ JSON'
    ThenReturnedNothing
}

Describe 'Install-WhiskeyDotNetTool.when installing version from global.json' {
    Init
    GivenGlobalJsonSdkVersion '2.1.505'
    WhenInstallingDotNetTool
    ThenReturnedValidDotNetPath
    ThenGlobalJsonVersion '2.1.505'
    ThenDotNetSdkVersion '2.1.505'
}

Describe 'Install-WhiskeyDotNetTool.when no version specified and global.json does not exist' {
    Init
    WhenInstallingDotNetTool
    ThenReturnedValidDotNetPath
    ThenGlobalJsonVersion (Get-DotNetLatestLtsVersion)
    ThenDotNetSdkVersion (Get-DotNetLatestLtsVersion)
}

try
{
    GivenDotNetNotInstalled

    Describe 'Install-WhiskeyDotNetTool.when specified version of DotNet does not exist globally' {
        Init
        GivenDotNetSuccessfullyInstalls
        GivenVersion '2.1.505'
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenGlobalJsonVersion '2.1.505'
        ThenDotNetLocallyInstalled '2.1.505'
    }

    Describe 'Install-WhiskeyDotNetTool.when specified version of DotNet exists globally' {
        Init
        GivenGlobalDotNetInstalled '2.1.505'
        GivenVersion '2.1.505'
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenGlobalJsonVersion '2.1.505'
        ThenDotNetNotLocallyInstalled '2.1.505'
    }

    Describe 'Install-WhiskeyDotNetTool.when installing DotNet and global.json exists in both install root and working directory' {
        Init
        GivenGlobalDotNetInstalled '1.1.11'
        GivenWorkingDirectory 'app'
        GivenGlobalJsonSdkVersion '1.0.1' -Directory $workingDirectory
        GivenGlobalJsonSdkVersion '2.1.505' -Directory $TestDrive.FullName
        GivenVersion '1.1.11'
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenDotNetNotLocallyInstalled
        ThenGlobalJsonVersion '1.1.11' -Directory $workingDirectory
        ThenGlobalJsonVersion '2.1.505' -Directory $TestDrive.FullName
    }
}
finally
{
    ThenRestoreOriginalPathEnvironment
}
