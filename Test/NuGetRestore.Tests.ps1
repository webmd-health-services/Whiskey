
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:packagesConfigPath = $null
    $script:version = $null
    $script:argument = $null
    $script:failed = $false
    $script:testDirPath = $null
    $script:testNum = 0

    function GivenArgument
    {
        param(
            $Argument
        )

        $script:argument = $Argument
    }

    function GivenFile
    {
        param(
            $Path,
            $Content
        )

        $fullPath = Join-Path -Path $script:testDirPath -ChildPath $Path
        New-Item -Path $fullPath -ItemType 'File' -Force
        $Content | Set-Content -Path $fullPath
    }

    function GivenSolution
    {
        param(
            $Name
        )

        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\{0}' -f $Name)
        Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $script:testDirPath -Recurse
    }

    function GivenPath
    {
        param(
            $Path
        )

        $script:packagesConfigPath = $Path
    }

    function GivenVersion
    {
        param(
            $Version
        )

        $script:version = $Version
    }

    function ThenPackageInstalled
    {
        param(
            $Name,

            $In
        )

        if( -not $In )
        {
            $In = $script:testDirPath
        }
        else
        {
            $In = Join-Path -Path $script:testDirPath -ChildPath $In
        }
        Join-Path -Path $In -ChildPath ('packages\{0}' -f $Name) | Should -Exist
    }

    function ThenPackageNotInstalled
    {
        param(
            $Name,

            $In
        )

        if( -not $In )
        {
            $In = $script:testDirPath
        }
        else
        {
            $In = Join-Path -Path $script:testDirPath -ChildPath $In
        }
        Join-Path -Path $In -ChildPath ('packages\{0}' -f $Name) | Should -Not -Exist
    }

    function WhenRestoringPackages
    {
        [CmdletBinding()]
        param(
        )

        $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testDirPath
        $parameter = @{ }
        if( $script:packagesConfigPath )
        {
            $parameter['Path'] = $script:packagesConfigPath
        }

        if( $script:version )
        {
            $parameter['Version']  = $script:version
        }

        if( $script:argument )
        {
            $parameter['Argument'] = $script:argument
        }

        $parameter['Verbose'] = $parameter['Debug'] = $true

        $VerbosePreference = 'Continue'
        $DebugPreference = 'Continue'
        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'NuGetRestore'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }

        $packagesDirPath = Join-Path -Path $script:testDirPath -ChildPath 'packages'
        if (Test-Path -Path $packagesDirPath)
        {
            Get-ChildItem -Path $packagesDirPath | Out-String | Write-Verbose -Verbose
        }
        else
        {
            Write-Verbose -Message "Packages directory ""${packagesDirPath}"" doesn't exist." -Verbose
        }
    }
}

Describe 'NuGetRestore' -Skip:((Test-Path -Path 'env:appveyor_build_worker_image') -and ($env:appveyor_build_worker_image -eq 'Visual Studio 2013')) {
    BeforeAll {
        $script:packagesConfigPath = $null
        $script:version = $null
        $script:argument = $null
        $script:failed = $false
        $script:testDirPath = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDirPath -ItemType 'Directory'
    }

    if (-not (Test-Path -Path 'variable:IsWindows'))
    {
        Set-Variable -Name 'IsWindows' -Value $true
    }

    Context 'Not on Windows' -Skip:($IsWindows) {
        It 'run on non-Windows platform' {
            WhenRestoringPackages -ErrorAction SilentlyContinue
            $script:failed | Should -BeTrue
            $Global:Error[0] | Should -Match 'Windows\ platform'
        }
    }

    Context 'On Windows' -Skip:(-not $IsWindows) {
        It 'restoring packages' {
            GivenFile 'packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="jQuery" version="3.7.1" targetFramework="net46" />
  <package id="NLog" version="5.3.4" targetFramework="net46" />
</packages>
'@
            GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
            GivenPath 'packages.config'
            WhenRestoringPackages
            ThenPackageInstalled 'NuGet.CommandLine.*'
            ThenPackageInstalled 'jQuery.3.7.1'
            ThenPackageInstalled 'NLog.5.3.4'
        }

        It 'restoring solution' {
            GivenSolution 'NUnit2PassingTest'
            GivenPath 'NUnit2PassingTest.sln'
            WhenRestoringPackages
            ThenPackageInstalled 'NuGet.CommandLine.*'
            ThenPackageInstalled 'NUnit.2.6.4'
        }

        It 'restoring multiple paths' {
            GivenFile 'subproject\packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="jQuery" version="3.7.1" targetFramework="net46" />
  <package id="NLog" version="5.3.4" targetFramework="net46" />
</packages>
'@
            GivenSolution 'NUnit2PassingTest'
            GivenPath 'subproject\packages.config','NUnit2PassingTest.sln'
            GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
            WhenRestoringPackages
            ThenPackageInstalled 'NuGet.CommandLine.*'
            ThenPackageInstalled 'jQuery.3.7.1'
            ThenPackageInstalled 'NLog.5.3.4'
            ThenPackageInstalled 'NUnit.2.6.4'
        }

        It 'pinning version of NuGet' {
            GivenFile 'packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="jQuery" version="3.7.1" targetFramework="net46" />
</packages>
'@
            GivenPath 'packages.config'
            GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
            GivenVersion '3.5.0'
            WhenRestoringPackages
            ThenPackageInstalled 'NuGet.CommandLine.3.5.0'
            ThenPackageInstalled 'jQuery.3.7.1'
        }
    }
}