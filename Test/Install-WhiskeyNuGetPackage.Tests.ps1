& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
function Init
{
    $script:threwException = $false
    $script:taskParameter = $null
    $script:taskWorkingDirectory = $TestDrive.FullName
    $script:result = $null
}

function WhenRunningNuGetInstall
{
    [CmdletBinding()]
    param(
        $Package,
        $Version
    )
    $Global:Error.Clear()
    try
    {
        $script:result = Install-WhiskeyNuGetPackage -Name $Package -Version $Version -DownloadRoot $TestDrive.FullName
    }
    catch
    {
    }
}

function ThenValidPackage
{
    param(
    )
        $Global:Error | Should -BeNullOrEmpty
        $script:result | Should -BeLike ('{0}\packages\*' -f $TestDrive.FullName)
        $script:result | Should -Exist
}

function ThenInvalidPackage
{
    param(
        $ExpectedError
    )

        $Global:Error | Should -Not -BeNullOrEmpty

        if ($script:result)
        {
            $script:result | Should -Not -Exist
        }
        if( $ExpectedError )
        {
            $Global:Error[0] | Should -Match $ExpectedError
        }
}

if( $IsWindows )
{
    Describe 'Install-WhiskeyNuGetPackage.when given a NuGet Package' {
        WhenRunningNuGetInstall -package 'NUnit.Runners' -version '2.6.4'
        It 'should exist and get installed into $DownloadRoot\packages' {
            ThenValidPackage
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet Pack is bad' {
        WhenRunningNuGetInstall -package 'BadPackage' -version '1.0.1' -ErrorAction SilentlyContinue
        It 'should write errors' {
            ThenInvalidPackage -ExpectedError 'failed\ with\ exit'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet Pack is empty string' {
        WhenRunningNuGetInstall -package '' -version '1.0.1' -ErrorAction SilentlyContinue
        It 'should write errors' {
            ThenInvalidPackage
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet pack Version is bad' {
        WhenRunningNuGetInstall -package 'Nunit.Runners' -version '0.0.0' -ErrorAction SilentlyContinue
        It 'should write errors' {
            ThenInvalidPackage -ExpectedError 'failed\ with\ exit'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when given a NuGet Package with an empty version string' {
        WhenRunningNuGetInstall -package 'NUnit.Runners' -version ''
        It 'should return the latest version and get installed into $DownloadRoot\packages' {
            ThenValidPackage
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when installing an already installed NuGet package' {

        WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'
        WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'

        It 'should not write any errors' {
            $Global:Error | Where-Object { $_ -notmatch '\bTestRegistry\b' } | Should -BeNullOrEmpty
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when set EnableNuGetPackageRestore' {
        Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
        Install-WhiskeyNuGetPackage -DownloadRoot $TestDrive.FullName -name 'NUnit.Runners' -version '2.6.4'
        It 'should enable NuGet package restore' {
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
        }
    }
}
else
{
    Describe 'Install-WhiskeyNuGetPackage.when run on non-Windows OS' {
        WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4' -InvalidPackage -ExpectedError 'Only\ supported\ on\ Windows'
    }
}

