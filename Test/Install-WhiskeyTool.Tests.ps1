& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$threwException = $false
$pathParameterName = 'ToolPath'
$versionParameterName = $null
$taskParameter = $null
$taskWorkingDirectory = $null

function GivenVersionParameterName
{
    param(
        $Name
    )

    $script:versionParameterName = $Name
}

function GivenWorkingDirectory
{
    param(
        $Directory
    )

    $script:taskWorkingDirectory = Join-Path -Path $TestDrive.FullName -ChildPath $Directory
    New-Item -Path $taskWorkingDirectory -ItemType Directory -Force | Out-Null
}

function Init
{
    $script:threwException = $false
    $script:taskParameter = $null
    $script:versionParameterName = $null
    $script:taskWorkingDirectory = $TestDrive.FullName
}

function ThenDotNetPathAddedToTaskParameter
{
    $taskParameter[$pathParameterName] | Should -Match '[\\/]dotnet(\.exe)$'
}

function ThenNodeInstalled
{
    param(
        [string]$NodeVersion,

        [string]$NpmVersion,

        [Switch]$AtLatestVersion
    )

    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName
    if( $AtLatestVersion )
    {
        $expectedVersion = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' |
                                ForEach-Object { $_ } |
                                Where-Object { $_.lts } |
                                Select-Object -First 1
        $NodeVersion = $expectedVersion.version
        if( -not $NpmVersion )
        {
            $NpmVersion = $expectedVersion.npm
        }
    }

    Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node-{0}-*-x64.*' -f $NodeVersion) | Should -Exist

    $nodePath | Should -Exist
    & $nodePath '--version' | Should -Be $NodeVersion

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $TestDrive.FullName -Global
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
    $npmPath | Should -Exist
    & $nodePath $npmPath '--version' | Should -Be $NpmVersion

    $taskParameter[$pathParameterName] | Should -Be (Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName)
}

function ThenNodeModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )

    $expectedPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -Global
    $expectedPath | Should -Exist
    $taskParameter[$pathParameterName] | Should -Be $expectedPath

    if( $AtVersion )
    {
        Get-Content -Path (Join-Path -Path $expectedPath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version' | Should -Be $AtVersion
    }
}

function ThenNodeModuleNotInstalled
{
    param(
        $Name
    )

    $nodeModulesPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -Global -ErrorAction Ignore | Should -BeNullOrEmpty
    $nodeModulesPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -ErrorAction Ignore | Should -BeNullOrEmpty
    $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
}

function ThenThrewException
{
    param(
        $Regex
    )

    $threwException | Should -Be $true
    $Global:Error[0] | Should -Match $Regex
}

function WhenInstallingTool
{
    [CmdletBinding()]
    param(
        $Name,
        $Parameter = @{ },
        $Version
    )

    $Global:Error.Clear()

    $toolAttribute = New-Object 'Whiskey.RequiresToolAttribute' $Name,$pathParameterName

    if( $versionParameterName )
    {
        $toolAttribute.VersionParameterName = $versionParameterName
    }

    if( $Version )
    {
        $toolAttribute.Version = $Version
    }

    $script:taskParameter = $Parameter

    Push-Location -path $taskWorkingDirectory
    try
    {
        Install-WhiskeyTool -ToolInfo $toolAttribute -InstallRoot $TestDrive.FullName -TaskParameter $Parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
    finally
    {
        Pop-Location
    }
}

Describe 'Install-WhiskeyTool.when installing Node and a Node module' {
    It 'should download Node package, install Node, install NPM, set path to node executable, and install the node module' {
        try
        {
            Init
            WhenInstallingTool 'Node'
            ThenNodeInstalled -AtLatestVersion
            WhenInstallingTool 'NodeModule::license-checker'
            ThenNodeModuleInstalled 'license-checker'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Install-WhiskeyTool.when installing Node and version defined by tool author' {
    It 'should download Node package, install Node, install NPM, should set path to node executable' {
        try
        {
            Init
            WhenInstallingTool 'Node' -Version '8.1.*'
            ThenNodeInstalled -NodeVersion 'v8.1.4' -NpmVersion '5.0.3'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Install-WhiskeyTool.when installing Node module and Node isn''t installed' {
    It 'should not install the node module, and throw and exception' {
        try
        {
            Init
            WhenInstallingTool 'NodeModule::license-checker' -ErrorAction SilentlyContinue
            ThenThrewException 'Node\ isn''t\ installed\ in\ your\ repository'
            ThenNodeModuleNotInstalled 'license-checker'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via version parameter' {
    It 'should install the node module' {
        try
        {
            Init
            Install-Node
            GivenVersionParameterName 'Fubar'
            WhenInstallingTool 'NodeModule::license-checker' @{ 'Fubar' = '13.1.0' } -Version '16.0.0'
            ThenNodeModuleInstalled 'license-checker' -AtVersion '13.1.0'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via RequiresTool attribute''s Version property' {
    It 'should install the node module' {
        try
        {
            Init
            Install-Node
            WhenInstallingTool 'NodeModule::nsp' @{ } -Version '2.7.0'
            ThenNodeModuleInstalled 'nsp' -AtVersion '2.7.0'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Install-WhiskeyTool.when installing .NET Core SDK' {
    It 'should set path to the dotnet executable, and call Install-WhiskeyDotNetTool' {
        Init
        Mock -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -MockWith { Join-Path -Path $InstallRoot -ChildPath '.dotnet\dotnet.exe' }
        GivenWorkingDirectory 'app'
        GivenVersionParameterName 'SdkVersion'
        WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' }
        ThenDotNetPathAddedToTaskParameter
        Assert-MockCalled -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $InstallRoot -eq $TestDrive.FullName -and `
            $WorkingDirectory -eq $taskWorkingDirectory -and `
            $version -eq '2.1.4'
        }
    }
}

Describe 'Install-WhiskeyTool.when .NET Core SDK fails to install' {
    It 'should throw an exception' {
        Init
        Mock -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -MockWith { Write-Error -Message 'Failed to install .NET Core SDK' }
        GivenVersionParameterName 'SdkVersion'
        WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' } -ErrorAction SilentlyContinue
        ThenThrewException 'Failed\ to\ install\ .NET\ Core\ SDK'
    }
}

function ThenDirectory
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

Describe 'Install-WhiskeyTool.when installing a PowerShell module' {
    It 'should install requested version' {
        Init
        GivenVersionParameterName 'Version'
        WhenInstallingTool 'PowerShellModule::Zip' -Parameter @{ 'Version' = '0.2.0' }
        ThenDirectory 'PSModules\Zip' -Exists
        $job = Start-Job { Import-Module -Name (Join-Path -Path $using:TestDrive.FullName -ChildPath 'PSModules\Zip') -PassThru }
        $moduleInfo = $job | Wait-Job | Receive-Job
        $moduleInfo.Version | Should -Be '0.2.0'
    }
}

Describe 'Install-WhiskeyTool.when failing to install a PowerShell module' {
    It 'should not install, and should throw an exception' {
        Init
        GivenVersionParameterName 'Version'
        WhenInstallingTool 'PowerShellModule::jfklfjsiomklmslkfs' -ErrorAction SilentlyContinue
        ThenDirectory 'PSModules\Whiskey' -Not -Exists
        ThenThrewException -Regex 'Failed\ to\ find'
    }
}

If ( $IsWindows )
{
    Describe 'Install-WhiskeyTool.when failing to install a NuGet Package' {
        It 'should not install, and should throw an exception' {
            Init
            WhenInstallingTool -Name 'NuGet::TROLOLO' -Version 'Version' -ErrorAction SilentlyContinue
            ThenDirectory 'packages\TROLOLO' -Not -Exists
            ThenThrewException -Regex 'failed\ to\ install'
        }
    }

    Describe 'Install-WhiskeyNuGetPackage.when NuGet is the provider' {
        It 'should enable NuGet package restore' {
            Init
            Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
            WhenInstallingTool 'NuGet::Nunit.Runners'
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
        }
    }

    Describe 'Install-WhiskeyTool.when NuGet is the provider and version specified' {
        It 'should enable NuGet package restore' {
            Init
            Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
            WhenInstallingTool 'NuGet::Nunit.Runners' -Version '2.6.1'
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Version -eq '2.6.1'}
        }
    }

    Describe 'Install-WhiskeyTool.when NuGet is the provider' {
        It 'should enable NuGet package restore' {
            Init
            Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
            WhenInstallingTool 'NuGet::Nunit.Runners' -Parameter @{ 'Version' = '2.6.4' } -Version '2.6.3'
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
            Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Version -eq '2.6.4'}
        }
    }
}
else {
    Describe 'Install-WhiskeyTool.when NuGet is the provider and running on non-Windows OS' {
        It 'should not install' {
            Init
            WhenInstallingTool 'NuGet::TROLOLO' -ErrorAction SilentlyContinue
            ThenDirectory 'packages\TROLOLO' -Not -Exists
            ThenThrewException 'Unable\ to\ install\ NuGet-based\ package'
        }
    }
}
