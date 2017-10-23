Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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

    It ('should write error message /{0}/' -f $Message) {
        $Global:Error | Should -Match $Message
    }
}

function ThenNoErrorsWritten
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $output | Should -BeNullOrEmpty
    }
}

function ThenReturnedVersion
{
    param(
        $Version
    )

    It ('should return version number ''{0}''' -f $Version) {
        $output | Should -Be $Version
    }
}

function ThenReturnedValidSemanticVersion
{
    It 'should return a valid semantic version number' {
        $output | Should -Match '^\d+\.\d+\.\d+.*'
    }
}

function ThenShouldNotRunNuget
{
    It 'should not run Nuget' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'list' } -Times 0
    }
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given only a package name' {
    Init
    GivenNuGetPackageName 'NuGet.CommandLine'
    WhenResolvingNuGetPackageVersion
    ThenReturnedValidSemanticVersion
    ThenNoErrorsWritten
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given a package name and Version number 1.2.3' {
    Init
    GivenNuGetPackageName 'NuGet.CommandLine'
    GivenVersion '1.2.3'
    WhenResolvingNuGetPackageVersion
    ThenShouldNotRunNuget
    ThenReturnedVersion '1.2.3'
    ThenNoErrorsWritten
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when given a package name and Version number that contains a wildcard' {
    Init
    GivenNuGetPackageName 'NuGet.CommandLine'
    GivenVersion '1.*'
    WhenResolvingNuGetPackageVersion -ErrorAction SilentlyContinue
    ThenShouldNotRunNuget
    ThenErrorMessage 'Wildcards are not allowed for NuGet packages yet because of a bug'
    ThenReturnedNothing
}

Describe 'Resolve-WhiskeyNuGetPackageVersion.when package does not exist' {
    Init
    GivenNuGetPackageName 'somenonexistentpackage'
    WhenResolvingNuGetPackageVersion -ErrorAction SilentlyContinue
    ThenErrorMessage 'Unable to find latest version of package'
    ThenReturnedNothing
}
