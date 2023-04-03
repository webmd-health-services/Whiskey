
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
}

BeforeAll {
    Set-StrictMode -Version 'Latest'

    $script:testRoot = $null
    $script:threwException = $false
    $script:taskParameter = $null
    $script:versionParameterName = $null
    $script:taskWorkingDirectory = $null
    $script:threwException = $false
    $script:pathParameterName = 'ToolPath'
    $script:versionParameterName = $null
    $script:taskParameter = $null
    $script:taskWorkingDirectory = $null

    function GivenVersionParameterName
    {
        param(
            $Name
        )

        $script:versionParameterName = $Name
    }

    function GivenWorkingDirectory
    {
        param(
            $Directory
        )

        $script:taskWorkingDirectory = Join-Path -Path $script:testRoot -ChildPath $Directory
        New-Item -Path $script:taskWorkingDirectory -ItemType Directory -Force | Out-Null
    }

    function ThenDirectory
    {
        param(
            $Path,
            [switch]$Not,
            [switch]$Exists
        )

        if( $Not )
        {
            Join-Path -Path $script:testRoot -ChildPath $Path | Should -Not -Exist
        }
        else
        {
            Join-Path -Path $script:testRoot -ChildPath $Path | Should -Exist
        }
    }

    function ThenDotNetPathAddedToTaskParameter
    {
        param(
            [Parameter(Mandatory)]
            [String]$Named
        )

        $script:taskParameter[$Named] | Should -Match '[\\/]dotnet(\.exe)$'
    }

    function ThenNodeInstalled
    {
        param(
            [String]$NodeVersion,

            [String]$NpmVersion,

            [switch]$AtLatestVersion,

            [String]$AndPathParameterIs
        )

        $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $script:testRoot
        if( $AtLatestVersion )
        {
            $expectedVersion = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' |
                                    ForEach-Object { $_ } |
                                    Where-Object { $_.lts } |
                                    Select-Object -First 1
            $NodeVersion = $expectedVersion.version
            if( -not $NpmVersion )
            {
                $NpmVersion = $expectedVersion.npm
            }
        }

        Join-Path -Path $script:testRoot -ChildPath ('.output\node-{0}-*-x64.*' -f $NodeVersion) | Should -Exist

        $nodePath | Should -Exist
        & $nodePath '--version' | Should -Be $NodeVersion
        $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $script:testRoot -Global
        $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
        $npmPath | Should -Exist
        & $nodePath $npmPath '--version' | Should -Be $NpmVersion
        $expectedNodePath = Resolve-WhiskeyNodePath -BuildRootPath $script:testRoot
        if( $AndPathParameterIs )
        {
            $script:taskParameter[$AndPathParameterIs] | Should -Be $expectedNodePath
        }
        else
        {
            $script:taskParameter.Values | Should -Not -Contain $expectedNodePath
            $Global:Error | Should -BeNullOrEmpty
        }
    }

    function ThenNodeModuleInstalled
    {
        param(
            $Name,
            $AtVersion,
            $AndPathParameterIs
        )

        $expectedPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:testRoot -Global
        $expectedPath | Should -Exist

        if( $AndPathParameterIs )
        {
            $script:taskParameter[$AndPathParameterIs] | Should -Be $expectedPath
        }
        else
        {
            $script:taskParameter.Values | Should -Not -Contain $expectedPath
            # NPM writes errors to STDERR which can sometimes cause builds to fail.
            $Global:Error | Where-Object { $_ -notmatch '\bnpm WARN\b' } |Should -BeNullOrEmpty
        }

        if( $AtVersion )
        {
            Get-Content -Path (Join-Path -Path $expectedPath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version' | Should -Be $AtVersion
        }
    }

    function ThenNodeModuleNotInstalled
    {
        param(
            $Name,
            $AndPathParameterIs
        )

        Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:testRoot -Global -ErrorAction Ignore | Should -BeNullOrEmpty
        Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:testRoot -ErrorAction Ignore | Should -BeNullOrEmpty
        $script:taskParameter.ContainsKey($AndPathParameterIs) | Should -BeFalse
    }

    function ThenThrewException
    {
        param(
            $Regex
        )

        $script:threwException | Should -BeTrue
        $Global:Error[0] | Should -Match $Regex
    }


    function WhenInstallingTool
    {
        [CmdletBinding(DefaultParameterSetName='HandleAttributeForMe')]
        param(
            [Parameter(ParameterSetName='FromAttribute')]
            [Whiskey.RequiresToolAttribute]$FromAttribute,

            [Parameter(ParameterSetName='HandleAttributeForMe',Position=0)]
            $Name,

            [Parameter(ParameterSetName='FromAttribute')]
            [Parameter(ParameterSetName='HandleAttributeForMe',Position=1)]
            $Parameter = @{ },

            [Parameter(ParameterSetName='HandleAttributeForMe')]
            $Version,

            [Parameter(ParameterSetName='HandleAttributeForMe')]
            [String]$PathParameterName
        )

        if( $PSCmdlet.ParameterSetName -eq 'HandleAttributeForMe' )
        {
            $FromAttribute = New-Object 'Whiskey.RequiresToolAttribute' $Name
            if( $PathParameterName )
            {
                $script:pathParameterName = $FromAttribute.PathParameterName = $PathParameterName
            }

            if( $script:versionParameterName )
            {
                $FromAttribute.VersionParameterName = $script:versionParameterName
            }

            if( $Version )
            {
                $FromAttribute.Version = $Version
            }
        }

        $script:taskParameter = $Parameter

        Push-Location -path $script:taskWorkingDirectory
        try
        {
            $Global:Error.Clear()
            Install-WhiskeyTool -ToolInfo $FromAttribute `
                                -InstallRoot $script:testRoot `
                                -OutFileRootPath (Join-Path -Path $script:testRoot -ChildPath '.output') `
                                -TaskParameter $Parameter
        }
        catch
        {
            $script:threwException = $true
            Write-Error -ErrorRecord $_
        }
        finally
        {
            Pop-Location
        }
    }

    function Invoke-NuGetInstall
    {
        [CmdletBinding()]
        param(
            $Package,
            $Version,

            [switch]$InvalidPackage,

            [String]$ExpectedError,

            [String[]] $WithDependencies
        )

        $result = $null
        try
        {
            $Global:Error.Clear()
            $result = Install-WhiskeyTool -DownloadRoot $script:testRoot -NugetPackageName $Package -Version $Version
        }
        catch
        {
        }

        if( -not $invalidPackage)
        {
            if( -not $Version )
            {
                $Version =
                    Find-Package -Name $Package -ProviderName 'NuGet' |
                    Select-Object -First 1 |
                    Select-Object -ExpandProperty 'Version'
            }
            $result | Should -Exist
            $result | Should -Be (Join-Path -Path $script:testRoot -ChildPath "packages\$($Package).$($Version)")

            if( $WithDependencies )
            {
                $packagesRoot = Join-Path -Path $script:testRoot -ChildPath 'packages'
                Get-ChildItem -Path $packagesRoot | Format-Table | Out-String | Write-Debug
                foreach( $dep in $WithDependencies )
                {
                    Join-Path -Path $packagesRoot -ChildPath $dep | Should -Exist
                }
            }
        }
        else
        {
            if( $result )
            {
                $result | Should -Not -Exist
            }
            # $Error has nuget.exe's STDERR depending on your console.
            $Global:Error.Count | Should -BeLessThan 9
            if( $ExpectedError )
            {
                $Global:Error[0] | Should -Match $ExpectedError
            }
        }
    }
}

# TODO: update tests to register a NuGet package source on non-Windows OSes. These should pass, since we no longer use
# nuget.exe.
Describe 'Install-WhiskeyTool' {
    BeforeEach {
        $Global:Error.Clear()
        $script:threwException = $false
        $script:taskParameter = $null
        $script:versionParameterName = $null
        $script:testRoot = New-WhiskeyTestRoot
        $script:taskWorkingDirectory = $script:testRoot
    }

    Context 'NuGet' -Skip:(-not $IsWindows) {
        It 'should install the package and its dependencies' {
            Invoke-NuGetInstall -package 'NUnit.Console' -version '3.15.0' -WithDependencies @(
                'NUnit.Console.3.15.0',
                'NUnit.ConsoleRunner.*',
                'NUnit.Extension.NUnitProjectLoader.*',
                'NUnit.Extension.NUnitV2Driver.*',
                'NUnit.Extension.NUnitV2ResultWriter.*',
                'NUnit.Extension.TeamCityEventListener.*',
                'NUnit.Extension.VSProjectLoader.*'
            )
        }

        It 'should validate package name' {
            Invoke-NuGetInstall -package 'BadPackage' -version '1.0.1' -invalidPackage -ErrorAction silentlyContinue
        }

        It 'should validate version' {
            Invoke-NugetInstall -package 'Nunit.Runners' -version '0.0.0' -invalidPackage -ErrorAction silentlyContinue
        }

        It 'should install the latest version' {
            Invoke-NuGetInstall -package 'NUnit.Runners' -version ''
        }

        It 'should handle package already installed' {
            Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            $Global:Error | Where-Object { $_ -notmatch '\bTestRegistry\b' } | Should -BeNullOrEmpty
        }

        It 'should enable NuGet package restore' {
            Install-WhiskeyTool -DownloadRoot $script:testRoot -NugetPackageName 'NUnit.Runners' -version '2.6.4'
        }
    }

    Context 'Node' {
        AfterEach {
            Remove-Node -BuildRoot $script:testRoot
        }

        It 'should install Node and the node module and set Node tool path' {
            WhenInstallingTool 'Node' -PathParameterName 'NodePath'
            ThenNodeInstalled -AtLatestVersion -AndPathParameterIs 'NodePath'
            WhenInstallingTool 'NodeModule::license-checker' -PathParameterName 'LicenseCheckerPath'
            ThenNodeModuleInstalled 'license-checker' -AndPathParameterIs 'LicenseCheckerPath'
        }

        It 'should install Node and the node module' {
            WhenInstallingTool 'Node'
            ThenNodeInstalled -AtLatestVersion
            WhenInstallingTool 'NodeModule::license-checker'
            ThenNodeModuleInstalled 'license-checker'
        }

        It 'should install the custom version' {
            WhenInstallingTool 'Node' -Version '8.1.*'
            ThenNodeInstalled -NodeVersion 'v8.1.4' -NpmVersion '5.0.3'
        }

        It 'should validate that Node is installed' {
            WhenInstallingTool 'NodeModule::license-checker' -PathParameterName 'LicenseCheckerPath' -ErrorAction SilentlyContinue
            ThenThrewException 'Node\ isn''t\ installed\ in\ your\ repository'
            ThenNodeModuleNotInstalled 'license-checker' -AndPathParameterIs 'LicenseCheckerPath'
        }

        It 'should install custom version of module' {
            Install-Node -BuildRoot $script:testRoot
            GivenVersionParameterName 'Fubar'
            WhenInstallingTool 'NodeModule::license-checker' @{ 'Fubar' = '25.0.0' } -Version '16.0.0'
            ThenNodeModuleInstalled 'license-checker' -AtVersion '25.0.0'
        }

        It 'should install tool author''s versionof module' {
            Install-Node -BuildRoot $script:testRoot
            WhenInstallingTool 'NodeModule::axios' @{ } -Version '0.21.1'
            ThenNodeModuleInstalled 'axios' -AtVersion '0.21.1'
        }
    }

    Context 'dotnet' {
        It 'should install dotNet Core' {
            Mock -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -MockWith { Join-Path -Path $InstallRoot -ChildPath '.dotnet\dotnet.exe' }
            GivenWorkingDirectory 'app'
            GivenVersionParameterName 'SdkVersion'
            WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' } -PathParameterName 'DotNetPath'
            ThenDotNetPathAddedToTaskParameter -Named 'DotNetPath'
            Assert-MockCalled -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
                $InstallRoot -eq $script:testRoot -and `
                $WorkingDirectory -eq $script:taskWorkingDirectory -and `
                $version -eq '2.1.4'
            }
        }

        It 'should handle installation failure' {
            Mock -CommandName 'Install-WhiskeyDotNetTool' `
                 -ModuleName 'Whiskey' `
                 -MockWith { Write-Error -Message 'Failed to install .NET Core SDK' -ErrorAction $PesterBoundParameters['ErrorAction'] }
            GivenVersionParameterName 'SdkVersion'
            WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' } #-ErrorAction SilentlyContinue
            ThenThrewException 'Failed\ to\ install\ .NET\ Core\ SDK'
        }
    }

    Context 'PowerShell' {
        It 'should install the module and pass module path to task' {
            Mock -CommandName 'Install-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -MockWith { return 'PSModulePath' }
            $attr = New-Object 'Whiskey.RequiresPowerShellModuleAttribute' -ArgumentList 'Zip'
            $attr.ModuleInfoParameterName = 'ZipModuleInfo'
            $attr.Version = '0.2.0'
            $attr.SkipImport = $true
            WhenInstallingTool -FromAttribute $attr
            $assertMockParams = @{
                'CommandName' = 'Install-WhiskeyPowerShellModule';
                'ModuleName' = 'Whiskey';
            }
            Assert-MockCalled @assertMockParams -ParameterFilter { $Name -eq 'Zip' }
            Assert-MockCalled @assertMockParams -ParameterFilter { $Version -eq '0.2.0' }
            Assert-MockCalled @assertMockParams -ParameterFilter { $BuildRoot -eq $script:testRoot }
            Assert-MockCalled @assertMockParams -ParameterFilter { $SkipImport -eq $true }
            Assert-MockCalled @assertMockParams -ParameterFilter { $PesterBoundParameters['ErrorAction'] -eq 'Stop' }
            $script:taskParameter['ZipModuleInfo'] | Should -Be 'PSModulePath'
        }

        It 'should install the module' {
            Mock -CommandName 'Install-WhiskeyPowerShellModule' -ModuleName 'Whiskey' -MockWith { return 'PSModulePath' }
            $attr = New-Object 'Whiskey.RequiresPowerShellModuleAttribute' -ArgumentList 'Zip'
            $attr.Version = '0.2.0'
            $attr.SkipImport = $true
            WhenInstallingTool -FromAttribute $attr
            $assertMockParams = @{
                'CommandName' = 'Install-WhiskeyPowerShellModule';
                'ModuleName' = 'Whiskey';
            }
            Assert-MockCalled @assertMockParams -ParameterFilter { $Name -eq 'Zip' }
            Assert-MockCalled @assertMockParams -ParameterFilter { $Version -eq '0.2.0' }
            Assert-MockCalled @assertMockParams -ParameterFilter { $BuildRoot -eq $script:testRoot }
            Assert-MockCalled @assertMockParams -ParameterFilter { $SkipImport -eq $true }
            Assert-MockCalled @assertMockParams -ParameterFilter { $PesterBoundParameters['ErrorAction'] -eq 'Stop' }
            $script:taskParameter.Values | Should -Not -BeOfType ([Management.Automation.PSModuleInfo])
        }
    }
}
