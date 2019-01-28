
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$packagesConfigPath = $null
$version = $null
$argument = $null
$failed = $false

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

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    New-Item -Path $fullPath -ItemType 'File' -Force
    $Content | Set-Content -Path $fullPath
}

function GivenSolution
{
    param(
        $Name
    )

    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\{0}' -f $Name)
    Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $TestDrive.FullName -Recurse
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

function Init
{
    $script:packagesConfigPath = $null
    $script:version = $null
    $script:argument = $null
    $script:failed = $false
}

function ThenPackageInstalled
{
    param(
        $Name,

        $In
    )

    if( -not $In )
    {
        $In = $TestDrive.FullName
    }
    else
    {
        $In = Join-Path -Path $TestDrive.FullName -ChildPath $In
    }
    It ('should install {0}' -f $Name) {
        Join-Path -Path $In -ChildPath ('packages\{0}' -f $Name) | Should -Exist
    }
}

function ThenPackageNotInstalled
{
    param(
        $Name,

        $In
    )

    if( -not $In )
    {
        $In = $TestDrive.FullName
    }
    else
    {
        $In = Join-Path -Path $TestDrive.FullName -ChildPath $In
    }
    It ('should install {0}' -f $Name) {
        Join-Path -Path $In -ChildPath ('packages\{0}' -f $Name) | Should -Not -Exist
    }
}

function WhenRestoringPackages
{
    [CmdletBinding()]
    param(
    )

    $context = New-WhiskeyTestContext -ForDeveloper
    $parameter = @{ }
    if( $packagesConfigPath )
    {
        $parameter['Path'] = $packagesConfigPath
    }

    if( $version )
    {
        $parameter['Version']  = $version
    }

    if( $argument )
    {
        $parameter['Argument'] = $argument
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

if( -not $IsWindows )
{
    Describe 'NuGetRestore.when run on non-Windows platform' {
        Init
        WhenRestoringPackages -ErrorAction SilentlyContinue
        It ('should fail') {
            $failed | Should -BeTrue
            $Global:Error[0] | Should -Match 'Windows\ platform'
        }
    }
    return
}

Describe 'NuGetRestore.when restoring packages' {
    Init
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

Describe 'NuGetRestore.when restoring solution' {
    Init 
    GivenSolution 'NUnit2PassingTest'
    GivenPath 'NUnit2PassingTest.sln'
    WhenRestoringPackages
    ThenPackageInstalled 'NuGet.CommandLine.*'
    ThenPackageInstalled 'NUnit.2.6.4'
}

Describe 'NuGetRestore.when restoring multiple paths' {
    Init
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

Describe 'NuGetRestore.when pinning version of NuGet' {
    Init
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