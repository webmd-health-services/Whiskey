
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDirPath = $null
    $script:allZipVersions = Find-Module -Name 'Zip' -AllVersions
    $script:latestZip = $script:allZipVersions | Select-Object -First 1
    $script:result = $null
    $script:expectedModuleName = $null
    $script:expectedModuleVersion = $null
    $script:installedModules = @()

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
        $parameter['BuildRoot'] = $script:testDirPath

        Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyPowerShellModule' -Parameter $PSBoundParameters -ErrorAction $ErrorActionPreference
    }

    function ThenModuleImported
    {
        param(
            [String]$AtVersion = $script:expectedModuleVersion,
            [String]$From
        )

        $module = Get-Module -Name $script:expectedModuleName
        $module | Should -Not -BeNullOrEmpty
        $module.Version | Should -Be $AtVersion
    }

    function ThenModuleInstalled
    {
        param(
            $Name = $script:expectedModuleName,
            $AtVersion = $script:expectedModuleVersion,
            $In = $TestPSModulesDirectoryName
        )

        $script:result | Should -Not -BeNullOrEmpty
        $path = $script:result.Path
        $errors = @()
        $module = Start-Job {
            Import-Module -Name $using:path -RequiredVersion $using:AtVersion -PassThru -WarningAction Ignore
        } | Wait-Job | Receive-Job -ErrorVariable 'errors'
        $errors | Should -BeNullOrEmpty
        $module | Should -Not -BeNullOrEmpty
        $module.Version | Should -Be $AtVersion

        Join-Path -Path $script:testDirPath -ChildPath "$($In)\$($Name)\$($AtVersion)" |
            Should -Exist
    }

    function ThenModuleInfoReturned
    {
        param(
            [String]$AtVersion = $script:expectedModuleVersion
        )

        $script:result | Should -Not -BeNullOrEmpty
        $script:result | Should -HaveCount 1
        $script:result | Should -BeOfType ([Management.Automation.PSModuleInfo])
        $script:result.Name | Should -Be $script:expectedModuleName
        $script:result.Version | Should -Be $AtVersion
    }

    function ThenModuleNotImported
    {
        Get-Module -Name $script:expectedModuleName | Should -BeNullOrEmpty
    }

    function ThenModuleNotInstalled
    {
        param(
            [String]$Named = $script:expectedModuleName,
            [String]$In
        )

        $rootPath = Join-Path -Path $script:testDirPath -ChildPath $In
        Join-Path -Path $rootPath -ChildPath $Named | Should -Not -Exist
    }

    function ThenNoErrors
    {
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenNoModuleInfoReturned
    {
        $script:result | Should -BeNullOrEmpty
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

        $script:installedModules = $script:installedModules
        $global:getWhiskeyPSModuleCalled = $false
        if( $script:installedModules )
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
                 } `
                 -MockWith { $script:installedModules | Write-Output }.GetNewClosure()
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

        Push-Location $script:testDirPath
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
}

Describe 'Install-WhiskeyPowerShellModule' {
    BeforeEach {
        $Global:Error.Clear()

        $script:expectedModuleName = $null
        $script:expectedModuleVersion = $null
        $script:result = $null
        $script:testDirPath = New-WhiskeyTestRoot
        $script:installedModules = @()

        Remove-Module -Name 'PackageManagement', 'PowerShellGet' -ErrorAction Ignore

        Initialize-WhiskeyTestPSModule -BuildRoot $script:testDirPath -Name 'PackageManagement', 'PowerShellGet'

        Reset-WhiskeyPSModulePath
        Unregister-WhiskeyPSModulesPath
    }

    AfterEach {
        Remove-Module -Name 'PackageManagement', 'PowerShellGet' -ErrorAction Ignore
        Reset-WhiskeyTestPSModule
        Reset-WhiskeyPSModulePath
        Register-WhiskeyPSModulesPath
    }

    It 'installs package management modules along with the module' {
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

    It 'allows omitting patch number from version' {
        WhenInstallingPSModule 'Zip' -Version '0.2'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion '0.2.0'
        ThenModuleInstalled -AtVersion '0.2.0'
        ThenModuleImported -AtVersion '0.2.0'
    }

    It 'allows omitting version' {
        WhenInstallingPSModule 'Zip'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
    }

    It 'reinstalls modules' {
        WhenInstallingPSModule 'Zip' -AtPath '.'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version -From '.'
        ThenModuleInstalled -AtVersion $script:latestZip.Version -In '.'

        # Re-install
        WhenInstallingPSModule 'Zip' -AtPath '.'
        ThenNoErrors
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version -From '.'
        ThenModuleInstalled -AtVersion $script:latestZip.Version -In '.'
    }

    It 'allows wildcards patterns in version number' {
        WhenInstallingPSModule 'Zip' -Version "$(([version]$script:latestZip.Version).Major).*"
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
    }

    It 'installs' {
        WhenInstallingPSModule 'Zip' -Version '0.2.0'
        ThenModuleInfoReturned
        ThenModuleInstalled
        ThenModuleImported
    }

    It 'validates given version of module exists' {
        $InformationPreference = 'Continue'
        $script:result = Install-PowerShellModule -Name 'Zip' -Version '0.0.1' -ErrorAction SilentlyContinue
        $script:result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }

    It 'validates version property has value' {
        $script:result = Install-PowerShellModule -Name 'Fubar' -Version '' -ErrorAction SilentlyContinue
        $script:result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error | Where-Object { $_ -match 'failed to find' } | Should -Not -BeNullOrEmpty
    }

    It 'reinstalls modules' {
        Install-PowerShellModule -Name 'Zip' -Version $script:latestZip.Version
        $info = Get-ChildItem -Path $script:testDirPath -Filter 'Zip.psd1' -Recurse
        $manifest = Test-ModuleManifest -Path $info.FullName
        Start-Sleep -Milliseconds 333
        Install-PowerShellModule -Name 'Zip' -Version $script:latestZip.Version
        $newInfo = Get-ChildItem -Path $script:testDirPath -Filter 'Zip.psd1' -Recurse
        $newManifest = Test-ModuleManifest -Path $newInfo.FullName
        $newManifest.Version | Should -Be $manifest.Version
    }

    It 'reinstalls over empty module directory' {
        $moduleRootDir = Join-Path -Path $script:testDirPath -ChildPath "$($TestPSModulesDirectoryName)\Zip"
        New-Item -Path $moduleRootDir -ItemType Directory | Write-WhiskeyDebug
        WhenInstallingPSModule -ForModule 'Zip' -Version $script:latestZip.Version
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version
    }

    It 'ensures module can be imported' {
        Install-PowerShellModule -Name 'Zip' -Version $script:latestZip.Version
        $moduleManifest = Join-Path -Path $script:testDirPath -ChildPath ('{0}\Zip\{1}\Zip.psd1' -f $TestPSModulesDirectoryName,$script:latestZip.Version) -Resolve
        '@{ }' | Set-Content -Path $moduleManifest
        { Test-ModuleManifest -Path $moduleManifest -ErrorAction Ignore } | Should -Throw
        $Global:Error.Clear()
        WhenInstallingPSModule -ForModule 'Zip' -Version $script:latestZip.Version
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version
    }

    It 'can skip importing the module' {
        WhenInstallingPSModule 'Zip' -SkipImport
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
        ThenModuleNotImported -AtVersion $script:latestZip.Version
    }

    It 'installs latest version when version omitted' {
        WhenInstallingPSModule 'Zip' -Version '0.1.*'
        ThenModuleInfoReturned -AtVersion '0.1.0'
        ThenModuleInstalled -AtVersion '0.1.0'
        ThenModuleImported -AtVersion '0.1.0'

        WhenInstallingPSModule 'Zip'
        ThenModuleInfoReturned -AtVersion $script:latestZip.Version
        ThenModuleInstalled -AtVersion $script:latestZip.Version
        ThenModuleImported -AtVersion $script:latestZip.Version
    }

    It 'always installs latest version that matches wildcard' {
        $newestVersion = $script:allZipVersions | Select-Object -First 1
        $previousVersion = $script:allZipVersions | Select-Object -Skip 1 | Select-Object -First 1
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

    It 'installs to global path even if module installed globally' {
        $globalModulePath =
            ($env:PSModulePath -split [IO.Path]::PathSeparator) |
            Where-Object { $_ -match '\b(Windows)?PowerShell\b' } |
            Select-Object -First 1
        Write-Verbose $globalModulePath -Verbose
        GivenModule 'Zip' -AtVersion $script:latestZip.Version -InstalledIn $globalModulePath
        WhenInstallingPSModule 'Zip' -Version $script:latestZip.Version -AtPath 'mycustompath'
        ThenModuleInfoReturned 'Zip' -AtVersion $script:latestZip.Version
        ThenModuleInstalled 'Zip' -AtVersion $script:latestZip.Version -In 'mycustompath'
        ThenModuleImported 'Zip' -AtVersion $script:latestZip.Version -From 'mycustompath'
        ThenModuleNotInstalled 'Zip' -In 'PSModules'
    }

    It 'fails build when module fails to install' {
        $Global:DebugPreference = $Global:VerbosePreference = 'Continue'
        try
        {
            Mock -CommandName 'Save-Module' -ModuleName 'Whiskey'
            { WhenInstallingPSModule 'Zip' -ErrorAction Stop } |
                Should -Throw '*the module doesn''t exist after running*'
            ThenNoModuleInfoReturned
            ThenModuleNotInstalled
            ThenModuleNotImported
        }
        finally
        {
            $Global:Error | Format-List * -Force | Out-String | Write-Debug
            $Global:DebugPreference = $Global:VerbosePreference = 'SilentlyContinue'
        }
    }

    It 'fails when can not remove old module' {
        $expectedVersion = $script:latestZip.Version
        $expectedPathWildcard = "*\PSModules\Zip\$($expectedVersion)\*"
        $parameterFilter = [scriptblock]::Create("{ `$Path -like ""$($expectedPathWildcard)""}")
        Mock -Command 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter $parameterFilter -MockWith { return $true }
        Mock -Command 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter $parameterFilter
        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath "PSModules\Zip\$($script:latestZip.Version)") -ItemType 'Directory'
        $slash = [IO.Path]::DirectorySeparatorChar
        $expectedMsg ="*the destination path "".$($slash)PSModules$($slash)Zip$($slash)$($expectedVersion)"" exists*"
        { WhenInstallingPSModule 'Zip' -ErrorAction Stop } | Should -Throw $expectedMsg
        ThenNoModuleInfoReturned
        ThenModuleNotInstalled
        ThenModuleNotImported
    }
}