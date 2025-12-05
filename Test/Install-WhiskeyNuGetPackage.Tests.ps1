
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey' -Resolve) -Verbose:$false

    $script:testDirPath = $null
    $script:testNum = 0
    $script:mockLocation = ''

    function GivenNuGetSource
    {
        param(
            [String] $Url
        )

        $script:mockLocation = $Url
    }

    function Get-NuGetPackageLatestVersion
    {
        param(
            [String] $PackageID
        )

        Invoke-RestMethod -Uri "https://azuresearch-usnc.nuget.org/query?q=packageid:${PackageID}" |
            Select-Object -ExpandProperty 'data' |
            Select-Object -ExpandProperty 'version'
    }
    function ThenDownloaded
    {
        param(
            [String] $Package,
            [String] $AtVersion
        )

        $expectedPath = Join-Path -Path $script:testDirPath -ChildPath "packages\${Package}.${AtVersion}"
        $expectedPath | Should -Exist
        Get-ChildItem -Path $expectedPath | Should -Not -BeNullOrEmpty
    }

    function ThenFile
    {
        param(
            [string] $At,

            [switch] $Not,

            [switch] $Exists
        )

        Join-Path -Path $script:testDirPath -ChildPath $At | Should -Not:$Not -Exist
    }

    function WhenDownloading
    {
        [CmdletBinding()]
        param(
            [String] $Package,

            [String] $AtVersion
        )

        $installArgs = @{ Package = $Package; BuildRootPath = $script:testDirPath }

        if ($AtVersion)
        {
            $installArgs['Version'] = $AtVersion
        }

        if ($PSBoundParameters.ContainsKey('ErrorAction'))
        {
            $installArgs['ErrorActionPreference'] = $PSBoundParameters['ErrorAction']
        }

        # Pester can't mock Get-PackageSource, so create an empty function here that Pester will mock instead of the
        # one in PackageManagement.
        function global:Get-PackageSource 
        {
            param(
            )
        }

        try
        {
            $mockLocation = $script:mockLocation
            Mock -CommandName 'Get-PackageSource' -ModuleName 'Whiskey' -MockWith {
                param(
                    $ProviderName,
                    $Location
                )
                [pscustomobject]@{ Name = 'NuGet.org'; Location = $mockLocation; ProviderName = 'NuGet' }
            }

            InModuleScope 'Whiskey' {
                $versionArg = @{}
                if ($Version)
                {
                    $versionArg['Version'] = $Version
                }
                Install-WhiskeyNuGetPackage -Name $Package -BuildRootPath $BuildRootPath @versionArg
            } -Parameters $installArgs
        }
        finally
        {
            if ((Test-Path -Path 'function:Get-PackageSource'))
            {
                Remove-Item -Path 'function:Get-PackageSource'
            }
        }
    }
}

BeforeDiscovery {
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssignments', '')]
    $nugetSources = & {
        'https://api.nuget.org/v3/index.json'
        # We can only test the NuGet v2 API on computers that don't have an API v3 NuGet source. PackageManagement fails
        # against the latest version of the NuGet v3 API on nuget.org and I don't know how to patch PackageManagement to
        # force it to use NuGet v2 API. YOu can't modify %APPDATA%\NuGet\NuGet.config because once Get-PackageSource
        # caches the sources and you have to restart PowerShell to pick up any changes. If you want to test both v2 and
        # v3, make sure your %AppData%\NuGet\NuGet.config file doesn't contain a v3 NuGet source.
        if (-not (Get-PackageSource -ProviderName 'NuGet' | Where-Object 'Location' -Like '*/v3/index.json'))
        {
            'https://www.nuget.org/api/v2'
        }
    }
}

Describe 'Install-WhiskeyNuGetPackage' {
    BeforeEach {
        $script:testDirPath = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDirPath -ItemType 'Directory'
        $Global:Error.Clear()
    }

    Context '<_>' -ForEach $nugetSources {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssignments', '')]
            $nugetSource = $_
        }

        BeforeEach {
            GivenNuGetSource $nugetSource
        }

        # Starting with Node.js 24.x.x only supported on Windows 10 and Server 2016 or higher.
        $is2012R2 = $false
        if ((Test-Path -Path 'variable:IsWindows') -and $IsWindows -and ((Get-CimInstance Win32_OperatingSystem).Caption -like "*Windows Server 2012 R2*"))
        {
            $is2012R2 = $true
        }
        It 'downloads NuGet.CommandLine' -Skip:$is2012R2 {
            $latestVersion = Get-NuGetPackageLatestVersion -PackageID 'NuGet.CommandLine'
            WhenDownloading 'NuGet.CommandLine'
            ThenDownloaded 'NuGet.CommandLine' -AtVersion $latestVersion
            ThenFile "packages\NuGet.CommandLine.${latestVersion}\tools\NuGet.exe" -Exists
        }

        It 'downloads NUnit.ConsoleRunner' {
            $latestVersion = Get-NuGetPackageLatestVersion -PackageID 'NUnit.ConsoleRunner'
            $latestVersion | Should -Not -BeNullOrEmpty
            WhenDownloading 'NUnit.ConsoleRunner'
            ThenDownloaded 'NUnit.ConsoleRunner' -AtVersion $latestVersion
            ThenFile "packages\NUnit.ConsoleRunner.${latestVersion}\tools\nunit3-console.exe" -Exists
        }

        It 'downloads NUnit.Runners' {
            WhenDownloading 'NUnit.Runners' -AtVersion '2.7.1'
            ThenDownloaded 'NUnit.Runners' -AtVersion '2.7.1'
            ThenFile "packages\NUnit.Runners.2.7.1\tools\nunit-console.exe" -Exists
        }

        It 'supports wildcard version <_>' -ForEach @('2.*', '2.7.*') {
            WhenDownloading 'NUnit.Runners' -AtVersion $_
            ThenDownloaded 'NUnit.Runners' -AtVersion '2.7.1'
            ThenFile "packages\NUnit.Runners.2.7.1\tools\nunit-console.exe" -Exists
        }

        It 'fails to download non existent package' {
            $pkgName = 'fmdskjoipfsdmkfdshu'
            WhenDownloading $pkgName -ErrorAction SilentlyContinue
            ThenFile ".output\nuget\${pkgName}.*" -Not -Exists
            ThenFile "packages\${pkgName}.*" -Not -Exists
        }

        It 'fails to download non existent version of package' {
            WhenDownloading 'NuGet.CommandLine' -AtVersion '5.99.99' -ErrorAction SilentlyContinue
            ThenFile '.output\nuget\NuGet.CommandLine.*' -Not -Exists
            ThenFile 'packages\NuGet.CommandLine.*' -Not -Exists
        }

        It 'installs packages with dependencies' -Skip:$is2012R2 {
            WhenDownloading 'NUnit.Console' -AtVersion '3.20.1'
            ThenDownloaded 'NUnit.Console' -AtVersion '3.20.1'
            $dependencies = @{
                'NUnit.ConsoleRunner' = '3.20.1';
                'NUnit.Extension.NUnitProjectLoader' = '3.8.0';
                'NUnit.Extension.NUnitV2Driver' = '3.9.0';
                'NUnit.Extension.NUnitV2ResultWriter' = '3.8.0';
                'NUnit.Extension.TeamCityEventListener' = '1.0.10';
                'NUnit.Extension.VSProjectLoader' = '3.9.0';
            }
            foreach ($depName in $dependencies.Keys)
            {
                $depVersion = $dependencies[$depName]
                ThenDownloaded $depName -AtVersion $depVersion
                ThenFile "packages\${depName}.${depVersion}\tools" -Exists
            }
        }

        # If accessing NuGet via a v2 API, ranges aren't supported.
        It 'supports NuGet version ranges' -Skip:($_ -like '*api/v2*') {
            # NuGet ranges favor lower versions over higher verions. 🤷‍♀️
            WhenDownloading 'NuGet.CommandLine' -AtVersion '[6.10,6.11)'
            ThenDownloaded 'NuGet.CommandLine' -AtVersion '6.10.0'
            ThenFile 'packages\NuGet.CommandLine.6.10.0\tools\NuGet.exe' -Exists
        }
    }
}