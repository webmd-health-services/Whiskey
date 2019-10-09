& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [String]$WithName,

        [String]$WithVersion
    )

    $dirName = '{0}.{1}' -f $WithName, $WithVersion
    $installRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [String]$WithName,

        [String]$WithVersion
    )

    $Global:Error.Clear()
    $params = @{}
    $params['Name'] = $WithName
    $params['Version'] = $WithVersion
    $params['BuildRoot'] = $TestDrive.FullName
    Invoke-WhiskeyPrivateCommand -Name 'Uninstall-WhiskeyNuGetPackage' -Parameter $params
}

function ThenNuGetPackageUninstalled
{
    [CmdLetBinding()]
    param(
        [String]$WithName,

        [String]$WithVersion
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    $uninstalledPath | Should -Not -Exist

    $Global:Error | Should -BeNullOrEmpty
}

function ThenNuGetPackageNotUninstalled
{
    [CmdLetBinding()]
    param(
        [String]$WithName,

        [String]$WithVersion
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name
    $uninstalledPath | Should Exist
    Remove-Item -Path $uninstalledPath -Recurse -Force
}

function ThenThrewErrors
{
    param(
        $ExpectedError
    )
    $Global:Error | Should -Not -BeNullOrEmpty
    if( $ExpectedError )
    {
        $Global:Error[0] | Should -Match $ExpectedError
    }

}

function ThenRanSuccessfully
{
    $Global:Error | Should -BeNullOrEmpty
}

if( $IsWindows )
{
    Describe 'Uninstall-WhiskeyNuGetPackage.when given a NuGet package' {
        It 'should successfully uninstall the NuGet package' {
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            WhenUninstallingNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            ThenRanSuccessfully
        }
    }

    Describe 'Uninstall-WhiskeyNuGetPackage.when given a NuGet package with an empty Version' {
        It 'should uninstall all NuGet package versions with the same name' {
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.OpenCover' -WithVersion '4.7.922'
            WhenUninstallingNuGetPackage -WithName 'NUnit.Runners'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            ThenNuGetPackageNotUninstalled -WithName 'NUnit.OpenCover' -WithVersion '4.7.922'
            ThenRanSuccessfully
        }
    }

    Describe 'Uninstall-WhiskeyNuGetPackage.when given a NuGet package with an empty string as a version' {
        It 'should uninstall all NuGet package versions with the same name' {
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.OpenCover' -WithVersion '4.7.922'
            WhenUninstallingNuGetPackage -WithName 'NUnit.Runners' -WithVersion ''
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            ThenNuGetPackageNotUninstalled -WithName 'NUnit.OpenCover' -WithVersion '4.7.922'
            ThenRanSuccessfully
        }
    }

    Describe 'Uninstall-WhiskeyNuGetPackage.when given a NuGet package with a pinned wildcard Version' {
        It 'should uninstall all NuGet package versions with the same name' {
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            GivenAnInstalledNuGetPackage -WithName 'NUnit.Runners' -WithVersion '3.6.4'
            WhenUninstallingNuGetPackage -WithName 'NUnit.Runners' -WithVersion '2.*'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.3'
            ThenNuGetPackageUnInstalled -WithName 'NUnit.Runners' -WithVersion '2.6.4'
            ThenNuGetPackageNotUninstalled -WithName 'NUnit.Runners' -WithVersion '3.6.4'
            ThenRanSuccessfully
        }
    }    

    Describe 'Uninstall-WhiskeyNuGetPackage.when given a NuGet package that does not exist' {
        It 'should stop and throw an error' {
            WhenUninstallingNuGetPackage -WithName 'NUnit.TROLOLO' -WithVersion '3.14.159' -ErrorAction SilentlyContinue
            ThenRanSuccessfully
        }
    }
}