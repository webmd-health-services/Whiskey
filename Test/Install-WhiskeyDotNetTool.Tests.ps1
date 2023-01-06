
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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
    Mock -CommandName 'Get-Command' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'dotnet' }
    if ( $IsWindows )
    {
        Mock -CommandName 'dotnet' -ModuleName 'Whiskey' -MockWith { 'return some strings'; cmd /c exit 1 }
    }
    else
    {
        Mock -CommandName 'dotnet' -ModuleName 'Whiskey' -MockWith { 'return some strings'; bash -c 'exit 1' }
    }
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

function GivenGlobalDotNetHasValidVersion
{
    param (
        $Version
    )

    if ( $IsWindows )
    {
        Mock -CommandName 'dotnet' -ModuleName 'Whiskey' -MockWith { $Version; cmd /c exit 0 }
    }
    else
    {
        Mock -CommandName 'dotnet' -ModuleName 'Whiskey' -MockWith { 'return some strings'; bash -c 'exit 0' }
    }
    Mock -CommandName 'Get-Command' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'dotnet' } -MockWith { 'A response' }.GetNewClosure()
}

function GivenBadGlobalJson
{
    @'
{
    "sdk": "version",

'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'global.json') -Force
}


function GivenGlobalJson
{
    param(
        $Version,
        $Directory = $TestDrive.FullName,
        $RollForward = [Whiskey.DotNetSdkRollForward]::Disable
    )

    @{
        'sdk' = @{
            'version' = $Version
            'rollForward' = [String] $RollForward
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
    Mock -CommandName 'Install-WhiskeyDotNetSdk' `
        -ModuleName 'Whiskey' `
        -MockWith {
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
    $dotNetSdkPath | Should -Exist
}

function ThenDotNetNotLocallyInstalled
{
    param(
        $Version
    )

    $dotNetSdkPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.dotnet\sdk\{0}' -f $Version)
    $dotNetSdkPath | Should -Not -Exist
}

function ThenDotNetSdkVersion
{
    param(
        [String]$Version
    )

    Push-Location -Path $workingDirectory
    try
    {
        & $dotnetPath --version | Should -Be $Version
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

    $Global:Error[0] | Should -Match $Message
}

function ThenReturnedNothing
{
    $dotnetPath | Should -BeNullOrEmpty
}

function ThenReturnedValidDotNetPath
{
    $dotnetPath | Should -Exist
}

function ThenReturnedDotNetExecutable
{
    $dotnetPath | Should -Be 'dotnet' -Because 'The version should already exist'
}

function ThenVersionToInstall
{
    param(
        [Version] $ExpectedVersion
    )

    Assert-MockCalled -CommandName 'Install-WhiskeyDotNetSdk' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter {
                        $Version -eq $ExpectedVersion
                      }
}

function ThenDotNetWasInstalled
{
    param(
        $Times = 1
    )
    Assert-MockCalled -CommandName 'Install-WhiskeyDotNetSdk' `
                      -ModuleName 'Whiskey' `
                      -Times $Times `
                      -Exactly
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

    $parameter = $PSBoundParameters
    $parameter['InstallRoot'] = $TestDrive.FullName;
    $parameter['WorkingDirectory'] = $workingDirectory
    $parameter['Version'] = $version

    $script:dotnetPath = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyDotNetTool' -Parameter $parameter
}

Describe 'Install-WhiskeyDotNetTool.when installing specific version' {
    It 'should install that version of .NET Core' {
        Init
        GivenVersion '2.1.505'
        GivenGlobalJson '2.1.300'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion '2.1.505'
    }
}

Describe 'Install-WhiskeyDotNetTool.when installing newer version' {
    It 'should overwrite the existing version' {
        Init
        GivenVersion '2.1.300'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenVersionToInstall -ExpectedVersion '2.1.300'

        GivenVersion '2.1.505'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion '2.1.505'
    }
}

Describe 'Install-WhiskeyDotNetTool.when given wildcard version' {
    It 'should install the most recent version' {
        Init
        GivenVersion '2.*'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        Write-Verbose $dotnetPath -Verbose
        ThenReturnedValidDotNetPath
        $expectedVersion = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyDotNetSdkVersion' -Parameter @{ 'Version' = '2.*'; }
        ThenVersionToInstall -ExpectedVersion $expectedVersion
    }
}

Describe 'Install-WhiskeyDotNetTool.when existing global.json contains invalid JSON' {
    It 'should fail' {
        Init
        GivenDotNetSuccessfullyInstalls
        GivenBadGlobalJson
        WhenInstallingDotNetTool -ErrorAction SilentlyContinue
        ThenError '\bcontains\ invalid\ JSON'
        ThenReturnedNothing
    }
}

Describe 'Install-WhiskeyDotNetTool.when installing version from global.json' {
    It 'should use the version in global.json' {
        Init
        GivenGlobalJson '2.1.505' -RollForward Disable
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion '2.1.505'
    }
}

Describe 'Install-WhiskeyDotNetTool.when no version specified and global.json does not exist' {
    It 'should install the latest LTS version of .NET Core' {
        Init
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion (Get-DotNetLatestLtsVersion)
    }
}


Describe 'Install-WhiskeyDotNetTool.when installing DotNet and global.json has Patch rollforward in global.json' {
    It 'should install latest patch for version' {
        Init
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenVersionToInstall -ExpectedVersion '2.1.526'
    }
}

Describe 'Install-WhiskeyDotNetTool.when installing DotNet and with invalid rollforward value' {
    It 'should use disabled for rollforward' {
        Init
        GivenGlobalJson -Version '2.1.500' -RollForward 'invalid'
        GivenDotNetSuccessfullyInstalls
        Mock -CommandName 'Resolve-WhiskeyDotNetSdkVersion' -ModuleName 'Whiskey' -MockWith { '2.1.500' }
        WhenInstallingDotNetTool
        ThenVersionToInstall -ExpectedVersion '2.1.500'
        Assert-MockCalled -CommandName 'Resolve-WhiskeyDotNetSdkVersion' `
                          -ModuleName 'Whiskey' `
                          -Times 1 `
                          -ParameterFilter { $RollForward -eq [Whiskey.DotNetSdkRollForward]::Disable }
    }
}


Describe 'Install-WhiskeyDotNetTool.when specified version of DotNet does not exist globally' {
    It 'should install .NET Core locally' {
        Init
        GivenDotNetSuccessfullyInstalls
        GivenVersion '2.1.505'
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenDotNetLocallyInstalled '2.1.505'
    }
}

Describe 'Install-WhiskeyDotNetTool.when specified version of DotNet exists globally' {
    It 'should install DotNet locally because Version parameter takes precedence' {
        Init
        GivenGlobalDotNetInstalled '2.1.505'
        GivenGlobalDotNetHasValidVersion -Version '2.1.505'
        GivenVersion '2.1.505'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenVersionToInstall '2.1.505'
        ThenDotNetLocallyInstalled '2.1.505'
        ThenReturnedValidDotNetPath
        ThenDotNetWasInstalled
    }
}

Describe 'Install-WhiskeyDotNetTool.when installing DotNet and global.json exists in both install root and working directory' {
    It 'should update working directory''s global.json file' {
        Init
        GivenGlobalDotNetInstalled '1.1.11'
        GivenWorkingDirectory 'app'
        GivenGlobalJson '1.0.1' -Directory $workingDirectory
        GivenGlobalJson '2.1.505' -Directory $TestDrive.FullName
        GivenGlobalDotNetHasValidVersion -Version '1.1.11'
        GivenVersion '1.1.11'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenDotNetLocallyInstalled
    }
}

Describe 'Install-WhiskeyDotNetTool.when installing DotNet and patch is lower than installed version' {
    It 'should use global.json''s version' {
        Init
        GivenGlobalDotNetInstalled '2.1.514'
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        GivenGlobalDotNetHasValidVersion -Version '2.1.514'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedDotNetExecutable
        ThenDotNetWasInstalled -Times 0
    }
}