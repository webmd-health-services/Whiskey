
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    if (-not (Test-Path -Path 'variable:IsWindows'))
    {
        $script:IsWindows = $true
        $script:IsLinux = $false
        $script:IsMacOS = $false
    }
}

BeforeAll {
    Set-StrictMode -Version 'Latest'
    
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null

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

        $WithVersion =
            Find-Package -Name $WithName -ProviderName 'NuGet' -AllVersions |
            Where-Object 'Version' -Like $WithVersion
            Select-Object -First 1 |
            Select-Object -ExpandProperty 'Version'
        if( -not $WithVersion )
        {
            return
        }
        $dirName = "$($WithName).$($WithVersion)"
        $installRoot = Join-Path -Path $script:testRoot -ChildPath 'packages'
        New-Item -Name $dirName -Path $installRoot -ItemType 'Directory' | Out-Null
    }

    function GivenFile
    {
        param(
            $Path
        )

        New-Item -Path (Join-Path -Path $script:testRoot -ChildPath $Path) -ItemType 'File' -Force
    }

    function GivenToolInstalled
    {
        param(
            $Name
        )

        New-Item -Path (Join-Path -Path $script:testRoot -ChildPath ('.{0}\{0}.exe' -f $Name)) -ItemType File -Force | Out-Null
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
            Join-Path -Path $script:testRoot -ChildPath $Path | Should -Not -Exist
        }
        else
        {
            Join-Path -Path $script:testRoot -ChildPath $Path | Should -Exist
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
        $path = Join-Path -Path $script:testRoot -ChildPath 'packages'
        $uninstalledPath = Join-Path -Path $path -ChildPath $Name

        $uninstalledPath | Should -Not -Exist

        $Global:Error | Should -beNullOrEmpty
    }

    function ThenNuGetPackageNotUninstalled
    {
        [CmdLetBinding()]
        param(
            [String]$WithVersion = '2.6.4',

            [String]$WithName = 'NUnit.Runners',

            [switch]$PackageShouldExist,

            [String]$WithError
        )

        $Name = '{0}.{1}' -f $WithName, $WithVersion
        $path = Join-Path -Path $script:testRoot -ChildPath 'packages'
        $uninstalledPath = Join-Path -Path $path -ChildPath $Name

        if( -not $PackageShouldExist )
        {
            $uninstalledPath | Should -Not -Exist
        }
        else
        {
            $uninstalledPath | Should -Exist
            Remove-Item -Path $uninstalledPath -Recurse -Force
        }

        $Global:Error | Should -Match $WithError
    }

    function ThenUninstalledDotNet
    {
        Join-Path -Path $script:testRoot -ChildPath '.dotnet' | Should -Not -Exist
    }

    function ThenUninstalledNode
    {
        Join-Path -Path $script:testRoot -ChildPath '.node' | Should -Not -Exist
    }

    function WhenUninstallingNuGetPackage
    {
        [CmdletBinding()]
        param(
            [String]$WithVersion = '2.6.4',

            [String]$WithName = 'NUnit.Runners'
        )

        $Global:Error.Clear()
        Uninstall-WhiskeyTool -NuGetPackageName $WithName -Version $WithVersion -BuildRoot $script:testRoot
    }

    function WhenUninstallingTool
    {
        [CmdletBinding()]
        param(
            [Whiskey.RequiresToolAttribute]$ToolInfo
        )

        Push-Location $script:testRoot
        try
        {
            Uninstall-WhiskeyTool -ToolInfo $ToolInfo -BuildRoot $script:testRoot
        }
        finally
        {
            Pop-Location
        }
    }
}

Describe 'Uninstall-WhiskeyTool' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot
        $Global:Error.Clear()
    }

    Context 'Windows' -Skip:(-not $IsWindows) {
        It 'deletes NuGet package' {
            GivenAnInstalledNuGetPackage
            WhenUninstallingNuGetPackage
            ThenNuGetPackageUnInstalled
        }

        It 'delete all versions of a NuGet package' {
            GivenAnInstalledNuGetPackage -WithVersion ''
            WhenUninstallingNuGetPackage -WithVersion ''
            ThenNuGetPackageUnInstalled -WithVersion ''
        }
    }

    It 'uninstalls node modules' {
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

    It 'uninstalls .NET' {
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

    It 'uninstalls PowerShell module' {
        $mockModulePath = '{0}\Whiskey\0.37.1\Whiskey.psd1' -f $TestPSModulesDirectoryName
        GivenFile $mockModulePath
        WhenUninstallingTool (New-Object 'Whiskey.RequiresPowerShellModuleAttribute' 'Whiskey')
        ThenFile $mockModulePath -Not -Exists
        ThenNoErrors
    }
}
