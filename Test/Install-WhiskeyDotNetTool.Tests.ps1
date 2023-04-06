
using module '..\Whiskey\Whiskey.Types.psm1'

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    if (-not (Get-Command -Name 'dotnet'))
    {
        Write-Error -Message 'These tests require that at least one .NET SDK is installed.' -ErrorAction Stop
        return
    }
}

BeforeAll {
    Set-StrictMode -Version 'Latest'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDir = $null
    $script:testNum = 0
    $script:returnValue = $null
    $script:globalDotNetDirectory = $null
    $script:originalPath = $env:PATH
    $script:workingDirectory = $null
    $script:installSdkReturnValue = $null
    $script:threwTerminatingError = $false

    $script:dotnetExeName = 'dotnet'
    if( $IsWindows )
    {
        $script:dotnetExeName = 'dotnet.exe'
    }

    function Get-DotNetLatestLtsVersion
    {
        Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' |
            Where-Object { $_ -match '(\d+\.\d+\.\d+)'} |
            Out-Null
        return $Matches[1]
    }

    function GivenDirectory
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named
        )

        New-Item -Path (Join-Path -Path $script:testDir -ChildPath $Named) -ItemType 'Directory' -Force
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
            [String] $Version,
            $Directory = $script:testDir,
            $RollForward = [WhiskeyDotNetSdkRollForward]::Disable
        )

        if (-not [IO.Path]::IsPathRooted($Directory))
        {
            $Directory = Join-Path -Path $script:testDir -ChildPath $Directory
        }

        @{
            'sdk' = @{
                'version' = $Version
                'rollForward' = [String] $RollForward
            }
        } | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path -Path $Directory -Child 'global.json') -Force
    }

    function GivenDotNetNotInstalled
    {
        Mock 'Get-Command' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Name -eq 'dotnet' } `
             -MockWith {
                $msg = "The term '${Name}' is not recognized as the name of a cmdlet, function, script file, or " +
                       'operable program. Check the spelling of the name, or if a path was included, verify that the ' +
                       'path is correct and try again.'
                Write-Error -Message $msg -ErrorAction $PesterBoundParameters['ErrorAction']
             }
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
            & $script:returnValue --version | Should -Be $Version
        }
        finally
        {
            Pop-Location
        }
    }

    function ThenError
    {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidAssignmentToAutomaticVariable', '')]
        [CmdletBinding()]
        param(
            [int] $AtIndex,
            [Parameter(Mandatory)]
            [String] $Matches
        )

        & {
                if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('AtIndex'))
                {
                    $Global:Error[$AtIndex] | Write-Output
                }
                else
                {
                    $Global:Error | Write-Output
                }
            } |
            Should -Match $Matches
    }

    function ThenReturnedNothing
    {
        $script:returnValue | Should -BeNullOrEmpty
    }

    function ThenReturnedDotNetPath
    {
        $script:returnValue | Should -Be $script:installSdkReturnValue
    }

    function ThenDotNetInstalled
    {
        param(
            [String] $AtVersion,

            [String] $InDirectory,

            [UInt32] $Times = 1
        )

        if ($InDirectory)
        {
            $InDirectory = Join-Path -Path $script:testDir -ChildPath $InDirectory
        }
        else
        {
            $InDirectory = $script:testDir
        }
        $InDirectory = Join-Path -Path $InDirectory -ChildPath '.dotnet'

        Should -Invoke 'Install-WhiskeyDotNetSdk' -ModuleName 'Whiskey' -Times $Times -Exactly

        if ($Times -eq 0)
        {
            return
        }

        Should -Invoke 'Install-WhiskeyDotNetSdk' `
               -ModuleName 'Whiskey' `
               -ParameterFilter { $InstallRoot -eq $InDirectory }

        if ($AtVersion)
        {
            Should -Invoke 'Install-WhiskeyDotNetSdk' `
                   -ModuleName 'Whiskey' `
                   -ParameterFilter {
                        $Version -eq $AtVersion
                    }
        }
    }

    function WhenInstallingDotNetTool
    {
        [CmdletBinding()]
        param(
            [String] $FromDirectory,

            [String] $Version
        )

        $Global:Error.Clear()

        Mock -CommandName 'Install-WhiskeyDotNetSdk' -ModuleName 'Whiskey' -MockWith { $script:installSdkReturnValue }

        $installArgs = @{}
        $installArgs['InstallRoot'] = $script:testDir
        if (-not $FromDirectory)
        {
            $FromDirectory = $script:testDir
        }

        if (-not [IO.Path]::IsPathRooted($FromDirectory))
        {
            $FromDirectory = Join-Path -Path $script:testDir -ChildPath $FromDirectory
        }

        $installArgs['WorkingDirectory'] = $FromDirectory
        $installArgs['Version'] = $version

        $script:threwTerminatingError = $false
        $curEA = $Global:ErrorActionPreference
        $Global:ErrorActionPreference = 'Stop'
        try
        {
            $script:returnValue = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyDotNetTool' -Parameter $installArgs
        }
        catch
        {
            $script:threwTerminatingError = $true
            Write-Error $_ -ErrorAction $ErrorActionPreference
        }
        finally
        {
            $Global:ErrorActionPreference = $curEA
        }
    }
}

Describe 'Install-WhiskeyDotNetTool' {
    BeforeEach {
        $script:testDir = Join-Path -Path $TestDrive -ChildPath $script:testNum
        New-Item -Path $script:testDir -ItemType Directory

        $script:installSdkReturnValue = [Guid]::NewGuid()
        $script:returnValue = $null
        $script:globalDotNetDirectory = Join-Path -Path $script:testDir -ChildPath 'GlobalDotNetSDK'
        $script:threwTerminatingError = $false
    }

    AfterEach {
        $script:testNum += 1
    }

    It 'should install specific version of dotNet' {
        GivenGlobalJson '2.1.300'
        WhenInstallingDotNetTool -Version '2.1.505'
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion '2.1.505'
    }

    It 'should install over an existing version' {
        WhenInstallingDotNetTool -Version '2.1.300'
        ThenDotNetInstalled -AtVersion '2.1.300'

        WhenInstallingDotNetTool -Version '2.1.505'
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion '2.1.505' -Times 2
    }

    It 'should allow wildcards in version numbers' {
        WhenInstallingDotNetTool -Version '2.*'
        ThenReturnedDotNetPath
        $expectedVersion = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyDotNetSdkVersion' -Parameter @{ 'Version' = '2.*'; }
        ThenDotNetInstalled -AtVersion $expectedVersion
    }

    It 'should handle invalid JSON in globalJson file' {
        GivenBadGlobalJson
        GivenDotNetNotInstalled
        WhenInstallingDotNetTool -ErrorAction SilentlyContinue
        ThenError -AtIndex 0 -Matches '\bcontains\ invalid\ JSON'
        ThenReturnedNothing
    }

    It 'should determine version to install from globalJson' {
        GivenGlobalJson '2.1.505' -RollForward Disable
        WhenInstallingDotNetTool
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion '2.1.505'
    }

    It 'should install the latest LTS version of dotNET' {
        GivenDotNetNotInstalled
        WhenInstallingDotNetTool
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion (Get-DotNetLatestLtsVersion)
    }

    It 'should install latest patch version' {
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        WhenInstallingDotNetTool
        ThenDotNetInstalled -AtVersion '2.1.526'
    }

    It 'should validate globalJson rollForward attribute' {
        GivenDotNetNotInstalled
        GivenGlobalJson -Version '2.1.500' -RollForward 'invalid'
        Mock -CommandName 'Resolve-WhiskeyDotNetSdkVersion' -ModuleName 'Whiskey' -MockWith { '2.1.500' }
        WhenInstallingDotNetTool
        ThenDotNetInstalled -AtVersion '2.1.500'
        Should -Invoke 'Resolve-WhiskeyDotNetSdkVersion' `
                       -ModuleName 'Whiskey' `
                       -Times 1 `
                       -ParameterFilter { $RollForward -eq [WhiskeyDotNetSdkRollForward]::Disable }
    }

    It 'should install dotNET locally' {
        WhenInstallingDotNetTool -Version '2.1.505'
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion '2.1.505'
    }

    It 'should install local dotNet instead of using global dotNET' {
        GivenGlobalDotNetHasValidVersion -Version '2.1.505'
        WhenInstallingDotNetTool -Version '2.1.505'
        ThenDotNetInstalled -AtVersion '2.1.505'
        ThenReturnedDotNetPath
        ThenDotNetInstalled -AtVersion '2.1.505'
    }

    It 'should use globalJson in working directory' {
        GivenDirectory 'app'
        GivenDotNetNotInstalled
        GivenGlobalJson '1.0.1' -Directory 'app'
        GivenGlobalJson '2.1.505'
        GivenGlobalDotNetHasValidVersion -Version '1.1.11'
        WhenInstallingDotNetTool -FromDirectory 'app' -Version '1.1.11'
        ThenDotNetInstalled -InDirectory $script:workingDirectory -AtVersion '1.1.101'
    }

    It 'should support patch for roll forward' {
        GivenDotNetNotInstalled
        GivenGlobalJson -Version '2.1.500' -RollForward Patch
        WhenInstallingDotNetTool
        ThenReturnedDotNetPath
        # Why not 2.1.818?! Because the hundreds digit of the patch version is actually the SDK feature band and when
        # rolling forward via patch, keeps to the same feature band.
        ThenDotNetInstalled -AtVersion '2.1.526'
    }

    It 'should handle newer SDK version in globalJson' {
        [Version] $sdkVersion = dotnet --version
        $sdkVersion = [Version]::New($sdkVersion.Major, $sdkVersion.Minor, 999)
        GivenGlobalJson $sdkVersion.ToString() -RollForward ([WhiskeyDotNetSdkRollForward]::LatestMajor)
        WhenInstallingDotNetTool
        $script:threwTerminatingError | Should -BeFalse
        ThenDotNetInstalled
    }

    It 'should allow empty roll forward' {
        GivenDotNetNotInstalled
        GivenGlobalJson '2.1.801' -RollForward ''
        $warnings = @()
        WhenInstallingDotNetTool -WarningVariable 'warnings'
        $warnings | Should -BeNullOrEmpty
        ThenDotNetInstalled -AtVersion '2.1.801'
    }
}