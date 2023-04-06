
using module '..\Whiskey\Whiskey.Types.psm1'

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDir = $null
    $script:testNum = 0
    $script:dotnetPath = $null
    $script:globalDotNetDirectory = $null
    $script:originalPath = $env:PATH
    $script:version = $null
    $script:workingDirectory = $null

    $script:dotnetExeName = 'dotnet'
    if( $IsWindows )
    {
        $script:dotnetExeName = 'dotnet.exe'
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

        New-Item -Path (Join-Path -Path $script:globalDotNetDirectory -ChildPath $script:dotnetExeName) -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path -Path $script:globalDotNetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)) -ItemType File -Force | Out-Null
        $env:PATH += ('{0}{1}' -f [IO.Path]::PathSeparator,$script:globalDotNetDirectory)
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

'@ | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath 'global.json') -Force
    }


    function GivenGlobalJson
    {
        param(
            $Version,
            $Directory = $script:testDir,
            $RollForward = [WhiskeyDotNetSdkRollForward]::Disable
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

        $script:workingDirectory = Join-Path -Path $script:testDir -ChildPath $Directory
        New-Item -Path $script:workingDirectory -ItemType Directory -Force | Out-Null
    }

    function GivenDotNetSuccessfullyInstalls
    {
        Mock -CommandName 'Install-WhiskeyDotNetSdk' `
            -ModuleName 'Whiskey' `
            -MockWith {
                $dotNetExePath = Join-Path -Path $InstallRoot -ChildPath $script:dotnetExeName
                New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

                $dotNetSdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)
                New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null

                return $dotNetExePath
            }
    }

    function GivenDotNetNotInstalled
    {
        $dotNetInstalls = Get-Command -Name $script:dotnetExeName -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
        foreach ($path in $dotNetInstalls)
        {
            $dotNetDirectory = [regex]::Escape(($path | Split-Path -Parent))
            $dotNetDirectory = ('{0}\\?' -f $dotNetDirectory)
            $env:PATH = $env:PATH -replace $dotNetDirectory,''
        }
    }

    function ThenRestoreOriginalPathEnvironment
    {
        $env:PATH = $script:originalPath
    }

    function ThenDotNetLocallyInstalled
    {
        param(
            $Version
        )

        $dotNetSdkPath = Join-Path -Path $script:testDir -ChildPath ('.dotnet\sdk\{0}' -f $Version)
        $dotNetSdkPath | Should -Exist
    }

    function ThenDotNetNotLocallyInstalled
    {
        param(
            $Version
        )

        $dotNetSdkPath = Join-Path -Path $script:testDir -ChildPath ('.dotnet\sdk\{0}' -f $Version)
        $dotNetSdkPath | Should -Not -Exist
    }

    function ThenDotNetSdkVersion
    {
        param(
            [String]$Version
        )

        Push-Location -Path $script:workingDirectory
        try
        {
            & $script:dotnetPath --version | Should -Be $Version
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
        $script:dotnetPath | Should -BeNullOrEmpty
    }

    function ThenReturnedValidDotNetPath
    {
        $script:dotnetPath | Should -Exist
    }

    function ThenReturnedDotNetExecutable
    {
        $script:dotnetPath | Should -Be 'dotnet' -Because 'The version should already exist'
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

        if (-not $script:workingDirectory)
        {
            $script:workingDirectory = $script:testDir
        }

        $parameter = $PSBoundParameters
        $parameter['InstallRoot'] = $script:testDir
        $parameter['WorkingDirectory'] = $script:workingDirectory
        $parameter['Version'] = $script:version

        $script:dotnetPath = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyDotNetTool' -Parameter $parameter
    }
}

Describe 'Install-WhiskeyDotNetTool' {
    BeforeEach {
        $script:testDir = Join-Path -Path $TestDrive -ChildPath $script:testNum
        New-Item -Path $script:testDir -ItemType Directory

        $script:dotnetPath = $null
        $script:globalDotNetDirectory = Join-Path -Path $script:testDir -ChildPath 'GlobalDotNetSDK'
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

    AfterEach {
        $script:testNum += 1
    }

    It 'should install specific version of dotNet' {
        GivenVersion '2.1.505'
        GivenGlobalJson '2.1.300'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion '2.1.505'
    }

    It 'should install over an existing version' {
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

    It 'should allow wildcards in version numbers' {
        GivenVersion '2.*'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        Write-Verbose $script:dotnetPath -Verbose
        ThenReturnedValidDotNetPath
        $expectedVersion = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyDotNetSdkVersion' -Parameter @{ 'Version' = '2.*'; }
        ThenVersionToInstall -ExpectedVersion $expectedVersion
    }

    It 'should handle invalid JSON in globalJson file' {
        GivenDotNetSuccessfullyInstalls
        GivenBadGlobalJson
        WhenInstallingDotNetTool -ErrorAction SilentlyContinue
        ThenError '\bcontains\ invalid\ JSON'
        ThenReturnedNothing
    }

    It 'should determine version to install from globalJson' {
        GivenGlobalJson '2.1.505' -RollForward Disable
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion '2.1.505'
    }

    It 'should install the latest LTS version of dotNET' {
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenVersionToInstall -ExpectedVersion (Get-DotNetLatestLtsVersion)
    }

    It 'should install latest patch version' {
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenVersionToInstall -ExpectedVersion '2.1.526'
    }

    It 'should validate globalJson rollForward attribute' {
        GivenGlobalJson -Version '2.1.500' -RollForward 'invalid'
        GivenDotNetSuccessfullyInstalls
        Mock -CommandName 'Resolve-WhiskeyDotNetSdkVersion' -ModuleName 'Whiskey' -MockWith { '2.1.500' }
        WhenInstallingDotNetTool
        ThenVersionToInstall -ExpectedVersion '2.1.500'
        Assert-MockCalled -CommandName 'Resolve-WhiskeyDotNetSdkVersion' `
                          -ModuleName 'Whiskey' `
                          -Times 1 `
                          -ParameterFilter { $RollForward -eq [WhiskeyDotNetSdkRollForward]::Disable }
    }

    It 'should install dotNET locally' {
        GivenDotNetSuccessfullyInstalls
        GivenVersion '2.1.505'
        WhenInstallingDotNetTool
        ThenReturnedValidDotNetPath
        ThenDotNetLocallyInstalled '2.1.505'
    }

    It 'should install local dotNet instead of using global dotNET' {
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

    It 'should use globalJson in working directory' {
        GivenGlobalDotNetInstalled '1.1.11'
        GivenWorkingDirectory 'app'
        GivenGlobalJson '1.0.1' -Directory $script:workingDirectory
        GivenGlobalJson '2.1.505' -Directory $script:testDir
        GivenGlobalDotNetHasValidVersion -Version '1.1.11'
        GivenVersion '1.1.11'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenDotNetLocallyInstalled
    }

    It 'should support patch for roll forward' {
        GivenGlobalDotNetInstalled '2.1.514'
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        GivenGlobalDotNetHasValidVersion -Version '2.1.514'
        GivenDotNetSuccessfullyInstalls
        WhenInstallingDotNetTool
        ThenReturnedDotNetExecutable
        ThenDotNetWasInstalled -Times 0
    }
}