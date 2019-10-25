

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

if( -not $IsWindows )
{
    return
}

$NuGetPackageName = $null
$output = $null
$version = $null

function Init
{
    $Global:Error.Clear()
    $Script:NuGetPackageName = $null
    $Script:output = $null
    $Script:version = $null
}

function GivenNuGetPackageName
{
    param(
        $Name
    )

    $Script:NuGetPackageName = $Name
}

function GivenNugetReturnsMultipleVersions
{
    param(
        [string[]]$PackageVersions
    )

    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'list' } -MockWith { $PackageVersions }.GetNewClosure()
}

function GivenVersion
{
    param(
        $Version
    )

    $Script:version = $Version
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'list' }
}

function WhenResolvingNuGetPackageVersion
{
    [CmdletBinding()]
    param()

    $Script:output = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $NuGetPackageName -Version $Version
}

function ThenErrorMessage
{
    param(
        $Message
    )

    $Global:Error | Should -Match $Message
}

function ThenNoErrorsWritten
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenReturnedNothing
{
    $output | Should -BeNullOrEmpty
}

function ThenReturnedVersion
{
    param(
        $Version
    )

    $output | Should -Be $Version
}

function ThenReturnedValidSemanticVersion
{
    $output | Should -Match '^\d+\.\d+\.\d+.*'
}

function ThenShouldNotRunNuget
{
    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'list' } -Times 0
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given only a package name' {
    It 'should get the latest version of that package' {
        Init
        GivenNuGetPackageName 'NuGet.CommandLine'
        WhenResolvingNuGetPackageVersion
        ThenReturnedValidSemanticVersion
        ThenNoErrorsWritten
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given a package name and Version number 1.2.3' {
    It 'should resolve that version of the pacakge' {
        Init
        GivenNuGetPackageName 'NuGet.CommandLine'
        GivenVersion '1.2.3'
        WhenResolvingNuGetPackageVersion
        ThenShouldNotRunNuget
        ThenReturnedVersion '1.2.3'
        ThenNoErrorsWritten
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given a package name and Version number that contains a wildcard' {
    It 'should fail' {
        Init
        GivenNuGetPackageName 'NuGet.CommandLine'
        GivenVersion '1.*'
        WhenResolvingNuGetPackageVersion -ErrorAction SilentlyContinue
        ThenShouldNotRunNuget
        ThenErrorMessage 'Wildcards are not allowed for NuGet packages yet because of a bug'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when package does not exist' {
    It 'should fail' {
        Init
        GivenNuGetPackageName 'somenonexistentpackage'
        WhenResolvingNuGetPackageVersion -ErrorAction SilentlyContinue
        ThenErrorMessage 'Unable to find latest version of package'
        ThenReturnedNothing
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when NuGet returns multiple versions' {
    It 'should return first' {
        Init
        GivenNuGetPackageName 'NuGet.CommandLine'
        GivenNugetReturnsMultipleVersions 'NuGet.CommandLine 1.2.3', 'NuGet.CommandLine 2.3.4'
        WhenResolvingNuGetPackageVersion
        ThenReturnedVersion '1.2.3'
        ThenNoErrorsWritten
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when NuGet returns multiple different packages' {
    It 'should return latest' {
        Init
        GivenNuGetPackageName 'NuGet.CommandLine'
        GivenNugetReturnsMultipleVersions 'NuGet.Command 1.0.0', 'NuGet.CommandLine', 'NuGet.CommandLine 4.3.0', 'NuGet.Core 2.1.0'
        WhenResolvingNuGetPackageVersion
        ThenReturnedVersion '4.3.0'
        ThenNoErrorsWritten
    }
}