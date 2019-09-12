& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$powerShellModulesDirectoryName = 'PSModules'

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
        $mockModulePath = '{0}\Whiskey\0.37.1\Whiskey.psd1' -f $powerShellModulesDirectoryName
        Init
        GivenFile $mockModulePath
        WhenUninstallingTool 'PowerShellModule::Whiskey'
        ThenFile $mockModulePath -Not -Exists
        ThenNoErrors
    }
}

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