& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Init
{
    $script:threwException = $false
    $script:taskParameter = $null
    $script:buildroot = $TestDrive.FullName
    $script:result = $null
}

function WhenRunningNuGetInstall
{
    [CmdletBinding()]
    param(
        $Package,
        $Version
    )

    $params = @{}
    $params['Name'] = $Package
    $params['Version'] = $Version
    $params['DownloadRoot'] = $TestDrive.FullName

    $Global:Error.Clear()
    try
    {
        $script:result = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNuGetPackage' -Parameter $params
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

        if ( $script:result )
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
        It 'should exist and get installed into $DownloadRoot\packages' {
            WhenRunningNuGetInstall -package 'NUnit.Runners' -version '2.6.4'
            ThenValidPackage
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet Pack is bad' {
        It 'should write errors' {
            WhenRunningNuGetInstall -package 'BadPackage' -version '1.0.1' -ErrorAction SilentlyContinue
            ThenInvalidPackage -ExpectedError 'failed\ to\ install'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet Pack is empty string' {
        It 'should write errors' {
            WhenRunningNuGetInstall -package '' -version '1.0.1' -ErrorAction SilentlyContinue
            ThenInvalidPackage -ExpectedError 'Cannot\ bind\ argument'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet pack Version is bad' {
        It 'should write errors' {
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '0.0.0' -ErrorAction SilentlyContinue
            ThenInvalidPackage -ExpectedError 'failed\ to\ install'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when given a NuGet Package with an empty version string' {
        It 'should return the latest version and get installed into $DownloadRoot\packages' {
            WhenRunningNuGetInstall -package 'NUnit.Runners' -version ''
            ThenValidPackage
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when installing an already installed NuGet package' {
        It 'should not write any errors' {
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            $Global:Error | Where-Object { $_ -notmatch '\bTestRegistry\b' } | Should -BeNullOrEmpty
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when set EnableNuGetPackageRestore' {
        It 'should enable NuGet package restore' {
            Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4'
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when install succeeded but path is missing' {
        It 'should write errors' {
            Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey'
            WhenRunningNuGetInstall -Package 'Nunit.Runners' -Version '2.6.4'
            Assert-MockCalled 'Invoke-Command' -ModuleName 'Whiskey'
            ThenInvalidPackage -ExpectedError 'but\ the\ module\ was\ not\ found'
        }
    }
}
else
{
    Describe 'Install-WhiskeyNuGetPackage.when run on non-Windows OS' {
        It 'should not run' {
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4' 
            ThenInvalidPackage -ExpectedError 'Only\ supported\ on\ Windows'
        }
    }
}

