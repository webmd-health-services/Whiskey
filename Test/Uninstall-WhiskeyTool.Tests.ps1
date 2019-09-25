& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$powerShellModulesDirectoryName = 'PSModules'

# Private Whiskey function. Define it so Pester doesn't complain about it not existing.
function Remove-WhiskeyFileSystemItem
{
}

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'

    )
    $WithVersion = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $WithName -Version $WithVersion
    if( -not $WithVersion )
    {
        return
    }
    $dirName = '{0}.{1}' -f $WithName, $WithVersion
    $installRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NuGet::NUnit.Runners'
    )

    $Global:Error.Clear()
    Uninstall-WhiskeyTool -Name $WithName -Version $WithVersion -InstallRoot $TestDrive.FullName
}

function ThenNuGetPackageUninstalled
{
    [CmdLetBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    It 'should successfully uninstall the NuGet Package' {
        $uninstalledPath | Should not Exist
    }

    It 'Should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
}

function ThenNuGetPackageNotUninstalled
{
        [CmdLetBinding()]
    param(
        [String]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners',

        [switch]
        $PackageShouldExist,

        [string]
        $WithError
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    if( -not $PackageShouldExist )
    {
        It 'should never have installed the package' {
            $uninstalledPath | Should not Exist
        }
    }
    else
    {
        It 'should not have uninstalled the existing package' {
            $uninstalledPath | Should Exist
        }
        Remove-Item -Path $uninstalledPath -Recurse -Force
    }

    It 'Should write errors' {
        $Global:Error | Should Match $WithError
    }
}

if( $IsWindows )
{
    Describe 'Uninstall-WhiskeyTool.when given an NuGet Package' {
        GivenAnInstalledNuGetPackage
        WhenUninstallingNuGetPackage
        ThenNuGetPackageUnInstalled
    }
    
    Describe 'Uninstall-WhiskeyTool.when given an NuGet Package with an empty Version' {
        GivenAnInstalledNuGetPackage -WithVersion ''
        WhenUninstallingNuGetPackage -WithVersion ''
        ThenNuGetPackageUnInstalled -WithVersion ''
    }
    
    Describe 'Uninstall-WhiskeyTool.when given an NuGet Package with a wildcard Version' {
        GivenAnInstalledNuGetPackage -WithVersion '2.*' -ErrorAction SilentlyContinue
        WhenUninstallingNuGetPackage -WithVersion '2.*' -ErrorAction SilentlyContinue
        ThenNuGetPackageNotUnInstalled -WithVersion '2.*' -WithError 'Wildcards are not allowed for NuGet packages'
    }    
}

$toolsInstallRoot = $null

function Init
{
    $Global:Error.Clear()
    $script:toolsInstallRoot = $TestDrive.FullName
}

function GivenFile
{
    param(
        $Path
    )

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path) -ItemType 'File' -Force
}

function GivenToolInstalled
{
    param(
        $Name
    )

    New-Item -Path (Join-Path -Path $toolsInstallRoot -ChildPath ('.{0}\{0}.exe' -f $Name)) -ItemType File -Force | Out-Null
}

function ThenFile
{
    param(
        $Path,

        [Switch]$Not,

        [Switch]$Exists
    )

    if( $Not )
    {
        Join-Path -Path $TestDrive.FullName -ChildPath $Path | Should -Not -Exist
    }
    else
    {
        Join-Path -Path $TestDrive.FullName -ChildPath $Path | Should -Exist
    }
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenUninstalledDotNet
{
    Join-Path -Path $toolsInstallRoot -ChildPath '.dotnet' | Should -Not -Exist
}

function ThenUninstalledNode
{
    Join-Path -Path $toolsInstallRoot -ChildPath '.node' | Should -Not -Exist
}

function WhenUninstallingTool
{
    param(
        $Name
    )

    Push-Location $TestDrive.FullName
    try
    {
        Uninstall-WhiskeyTool -Name $Name -InstallRoot $toolsInstallRoot
    }
    finally
    {
        Pop-Location
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling Node and node modules' {
    It 'should use Remove-WhiskeyFileSystemItem to delete node' {
        try
        {
            Init
            GivenToolInstalled 'node'
            WhenUninstallingTool 'Node'
            WhenUninstallingTool 'NodeModule::rimraf'
            ThenUninstalledNode
            ThenNoErrors
    
            # Also ensure Remove-WhiskeyFileSystemItem is used to delete the tool
            Mock -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
            GivenToolInstalled 'node'
            WhenUninstallingTool 'Node'
            Assert-MockCalled -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
        }
        finally
        {
            Remove-Node
        } 
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling DotNet SDK' {
    It 'should use Remove-WhiskeyFileSystemItem to delete .Net Core SDK' {
        Init
        GivenToolInstalled 'DotNet'
        WhenUninstallingTool 'DotNet'
        ThenUninstalledDotNet
        ThenNoErrors
    
        # Also ensure Remove-WhiskeyFileSystemItem is used to delete the tool
        Mock -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
        GivenToolInstalled 'DotNet'
        WhenUninstallingTool 'DotNet'
        Assert-MockCalled -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling PowerShell module' {
    It 'should uninstall the module' {
        $mockModulePath = '{0}\Foo\0.37.1\Foo.psd1' -f $powerShellModulesDirectoryName
        Init
        GivenFile $mockModulePath
        WhenUninstallingTool 'PowerShellModule::Foo'
        ThenFile $mockModulePath -Not -Exists
        ThenNoErrors
    }
}

if ( $IsWindows )
{
    Describe 'Uninstall-WhiskeyTool.when uninstalling a NuGet package' {
        It 'should call uninstall the package' {
            $mockPackagePath = '\packages\NUnit.Console.3.10.0\NUnit.Console.3.10.0.nupkg'
            Init
            GivenFile $mockPackagePath
            WhenUninstallingTool 'NuGet::NUnit.Console'
            ThenFile $mockPackagePath -Not -Exists
            ThenNoErrors
        }
    }
}