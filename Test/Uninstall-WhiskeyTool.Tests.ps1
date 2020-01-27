& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null

# Private Whiskey function. Define it so Pester doesn't complain about it not existing.
function Remove-WhiskeyFileSystemItem
{
}

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [String]$WithVersion = '2.6.4',

        [String]$WithName = 'NUnit.Runners'
    )
    $dirName = '{0}.{1}' -f $WithName, $WithVersion
    $installRoot = Join-Path -Path $testRoot -ChildPath 'packages'
    New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
}

function GivenFile
{
    param(
        [String]$Path
    )

    New-Item -Path (Join-Path -Path $testRoot -ChildPath $Path) -ItemType 'File' -Force
}

function GivenToolInstalled
{
    param(
        $Name
    )

    New-Item -Path (Join-Path -Path $testRoot -ChildPath ('.{0}\{0}.exe' -f $Name)) -ItemType File -Force | Out-Null
}

function Init
{
    $Global:Error.Clear()
    $script:testRoot = New-WhiskeyTestRoot
}

function ThenFile
{
    param(
        $Path,
        [switch]$Not,
        [switch]$Exists
    )

    if( $Not )
    {
        Join-Path -Path $testRoot -ChildPath $Path | Should -Not -Exist
    }
    else
    {
        Join-Path -Path $testRoot -ChildPath $Path | Should -Exist
    }
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenNuGetPackageUninstalled
{
    [CmdLetBinding()]
    param(

        [String]$WithVersion = '2.6.4',

        [String]$WithName = 'NUnit.Runners'
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $testRoot -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    $uninstalledPath | Should -Not -Exist

    $Global:Error | Should -BeNullOrEmpty
}

function ThenNuGetPackageNotUninstalled
{
    [CmdLetBinding()]
    param(
        [String]$WithName,

        [String]$WithVersion,

        [String]$WithError
    )

    $Name = '{0}.{1}' -f $WithName, $WithVersion
    $path = Join-Path -Path $testRoot -ChildPath 'packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    $uninstalledPath | Should -Exist
    Remove-Item -Path $uninstalledPath -Recurse -Force

    if( $WithError )
    {
        $Global:Error[0] | Should -Match $WithError
    }
    else
    {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenUninstalledDotNet
{
    Join-Path -Path $testRoot -ChildPath '.dotnet' | Should -Not -Exist
}

function ThenUninstalledNode
{
    Join-Path -Path $testRoot -ChildPath '.node' | Should -Not -Exist
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [String]$WithVersion = '2.6.4',

        [String]$WithName = 'NUnit.Runners'
    )

    $Global:Error.Clear()
    Uninstall-WhiskeyTool -NuGetPackageName $WithName -Version $WithVersion -BuildRoot $testRoot
}

function WhenUninstallingTool
{
    [CmdletBinding()]
    param(
        [Whiskey.RequiresToolAttribute]$ToolInfo
    )

    Push-Location $testRoot
    try
    {
        Uninstall-WhiskeyTool -ToolInfo $ToolInfo -BuildRoot $testRoot
    }
    finally
    {
        Pop-Location
    }
}

if( $IsWindows )
{

    Describe 'Uninstall-WhiskeyTool.when given an NuGet Package' {
        It 'Should pass the correct parameters to Uninstall-WhiskeyNuGetPackage' {
            Init
            Mock 'Uninstall-WhiskeyNuGetPackage' -Module 'Whiskey'
            $toolobject = New-Object 'Whiskey.RequiresToolAttribute' 'NuGet::NUnit.Runners'
            $toolobject.version = '2.6.4'
            WhenUninstallingTool $toolobject
            Assert-MockCalled 'Uninstall-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
                $Name -eq 'NUnit.Runners'
                $DownloadRoot -eq $testRoot
                $Version -eq '2.6.4'
            }
        }
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling Node and node modules' {
    It 'should uninstall everything' {
        Init
        GivenToolInstalled 'node'
        WhenUninstallingTool (New-Object 'Whiskey.RequiresToolAttribute' 'Node')
        WhenUninstallingTool (New-Object 'Whiskey.RequiresToolAttribute' 'NodeModule::rimraf')
        ThenUninstalledNode
        ThenNoErrors

        # Also ensure Remove-WhiskeyFileSystemItem is used to delete the tool
        Mock -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
        GivenToolInstalled 'node'
        WhenUninstallingTool (New-Object 'Whiskey.RequiresToolAttribute' 'Node')
        Assert-MockCalled -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling DotNet SDK' {
    It 'should remove dotNet SDK' {
        Init
        GivenToolInstalled 'DotNet'
        WhenUninstallingTool (New-Object 'Whiskey.RequiresToolAttribute' 'DotNet')
        ThenUninstalledDotNet
        ThenNoErrors

        # Also ensure Remove-WhiskeyFileSystemItem is used to delete the tool
        Mock -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
        GivenToolInstalled 'DotNet'
        WhenUninstallingTool (New-Object 'Whiskey.RequiresToolAttribute' 'DotNet')
        Assert-MockCalled -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
    }
}

Describe 'Uninstall-WhiskeyTool.when uninstalling PowerShell module' {
    It 'should delete PowerShell module' {
        Init
        $mockModulePath = '{0}\Whiskey\0.37.1\Whiskey.psd1' -f $TestPSModulesDirectoryName
        Init
        GivenFile $mockModulePath
        WhenUninstallingTool (New-Object 'Whiskey.RequiresPowerShellModuleAttribute' 'Whiskey')
        ThenFile $mockModulePath -Not -Exists
        ThenNoErrors
    }
}
