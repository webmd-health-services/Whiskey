& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Init
{
    $script:threwException = $false
    $script:taskParameter = $null
    $script:testroot = New-WhiskeyTestRoot
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
    $params['DownloadRoot'] = $testroot

    $Global:Error.Clear()
    try
    {
        $script:result = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNuGetPackage' -Parameter $params
    }
    catch
    {
    }
}

function ThenPackageInstalled
{
    param(
        $WithName,
        $WithVersion
    )

        $Global:Error | Should -BeNullOrEmpty
        $script:result | Should -BeLike ('{0}\packages\{1}.{2}' -f $testroot, $WithName, $WithVersion)
        $script:result | Should -Exist
}

function ThenPackageNotInstalled
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
            Init
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4'
            ThenPackageInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.4'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when package does not exist' {
        It 'should write errors' {
            Init
            WhenRunningNuGetInstall -Package 'BadPackage' -Version '1.0.1' -ErrorAction SilentlyContinue
            ThenPackageNotInstalled -ExpectedError 'failed\ to\ install'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when package name is empty' {
        It 'should write errors' {
            Init
            WhenRunningNuGetInstall -Package '' -Version '1.0.1' -ErrorAction SilentlyContinue
            ThenPackageNotInstalled -ExpectedError 'Cannot\ bind\ argument'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when package version does not exist' {
        It 'should write errors' {
            Init
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '0.0.0' -ErrorAction SilentlyContinue
            ThenPackageNotInstalled -ExpectedError 'failed\ to\ install'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when package version is empty' {
        It 'should return the latest version and get installed into $DownloadRoot\packages' {
            Init
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version ''
            ThenPackageInstalled -WithName 'NUnit.Runners' -WithVersion '3.10.0'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when installing an already installed NuGet package' {
        It 'should not write any errors' {
            Init
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            WhenRunningNuGetInstall -package 'Nunit.Runners' -version '2.6.4'
            $Global:Error | Where-Object { $_ -notmatch '\bTestRegistry\b' } | Should -BeNullOrEmpty
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when package restore is not enabled' {
        It 'should enable NuGet package restore' {
            Init
            Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4'
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
            Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when install succeeded but path is missing' {
        It 'should write errors' {
            Init
            Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey'
            WhenRunningNuGetInstall -Package 'Nunit.Runners' -Version '2.6.4'
            Assert-MockCalled 'Invoke-Command' -ModuleName 'Whiskey'
            ThenPackageNotInstalled -ExpectedError 'but\ the\ module\ was\ not\ found'
        }
    }
}
else
{
    Describe 'Install-WhiskeyNuGetPackage.when run on non-Windows OS' {
        It 'should not run' {
            Init
            WhenRunningNuGetInstall -Package 'NUnit.Runners' -Version '2.6.4' 
            ThenPackageNotInstalled -ExpectedError 'Only\ supported\ on\ Windows'
        }
    }
}

