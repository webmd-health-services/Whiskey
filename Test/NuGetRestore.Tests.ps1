
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDir = $null
    $script:testNum = 0
    $script:packagesConfigPath = $null
    $script:version = $null
    $script:argument = $null
    $script:failed = $false

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

        $fullPath = Join-Path -Path $script:testDir -ChildPath $Path
        New-Item -Path $fullPath -ItemType 'File' -Force
        $Content | Set-Content -Path $fullPath
    }

    function GivenSolution
    {
        param(
            $Name
        )

        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\{0}' -f $Name)
        Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $script:testDir -Recurse
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
            $In = $script:testDir
        }
        else
        {
            $In = Join-Path -Path $script:testDir -ChildPath $In
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
            $In = $script:testDir
        }
        else
        {
            $In = Join-Path -Path $script:testDir -ChildPath $In
        }
        Join-Path -Path $In -ChildPath ('packages\{0}' -f $Name) | Should -Not -Exist
    }

    function WhenRestoringPackages
    {
        [CmdletBinding()]
        param(
        )

        $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testDir
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

        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'NuGetRestore'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'NuGetRestore' {
    BeforeEach {
        $Global:Error.Clear()
        $script:packagesConfigPath = $null
        $script:version = $null
        $script:argument = $null
        $script:failed = $false
        $script:testDir = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDir -ItemType Directory
    }

    if ((Get-Variable -Name 'IsWindows' -ErrorAction Ignore) -and -not $IsWindows)
    {
        It 'fails on non-Windows platform' {
            WhenRestoringPackages -ErrorAction SilentlyContinue
            $script:failed | Should -BeTrue
            $Global:Error[0] | Should -Match 'Windows\ platform'
        }
        return
    }

    It 'restores packages' {
        GivenFile 'packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
<package id="jQuery" version="3.1.1" targetFramework="net46" />
<package id="NLog" version="4.3.10" targetFramework="net46" />
</packages>
'@
        GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
        GivenPath 'packages.config'
        WhenRestoringPackages
        ThenPackageInstalled 'NuGet.CommandLine.*'
        ThenPackageInstalled 'jQuery.3.1.1'
        ThenPackageInstalled 'NLog.4.3.10'
    }

    It 'restores solution' {
        GivenSolution 'NUnit2PassingTest'
        GivenPath 'NUnit2PassingTest.sln'
        WhenRestoringPackages
        ThenPackageInstalled 'NuGet.CommandLine.*'
        ThenPackageInstalled 'NUnit.2.6.4'
    }

    It 'restores multiple paths' {
        GivenFile 'subproject\packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
<package id="jQuery" version="3.1.1" targetFramework="net46" />
<package id="NLog" version="4.3.10" targetFramework="net46" />
</packages>
'@
        GivenSolution 'NUnit2PassingTest'
        GivenPath 'subproject\packages.config','NUnit2PassingTest.sln'
        GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
        WhenRestoringPackages
        ThenPackageInstalled 'NuGet.CommandLine.*'
        ThenPackageInstalled 'jQuery.3.1.1'
        ThenPackageInstalled 'NLog.4.3.10'
        ThenPackageInstalled 'NUnit.2.6.4'
    }

    It 'uses custom version of NuGet' {
        GivenFile 'packages.config' @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
<package id="jQuery" version="3.1.1" targetFramework="net46" />
</packages>
'@
        GivenPath 'packages.config'
        GivenArgument @( '-PackagesDirectory', '$(WHISKEY_BUILD_ROOT)\packages' )
        GivenVersion '3.5.0'
        WhenRestoringPackages
        ThenPackageInstalled 'NuGet.CommandLine.3.5.0'
        ThenPackageInstalled 'jQuery.3.1.1'
    }
}