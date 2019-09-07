
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
    It ('should set path to the dotnet executable') {
        $taskParameter[$pathParameterName] | Should -Match '[\\/]dotnet(\.exe)$'
    }
}

function ThenNodeInstalled
{
    param(
        [string]
        $NodeVersion,

        [string]
        $NpmVersion,

        [Switch]
        $AtLatestVersion
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

    It ('should download Node package') {
        Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node-{0}-*-x64.*' -f $NodeVersion) | Should -Exist
    }

    It ('should install Node') {
        $nodePath | Should -Exist
        & $nodePath '--version' | Should -Be $NodeVersion
    }

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $TestDrive.FullName -Global
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
    It ('should install NPM') {
        $npmPath | Should -Exist
        & $nodePath $npmPath '--version' | Should -Be $NpmVersion
    }

    It ('should set path to node executable') {
        $taskParameter[$pathParameterName] | Should -Be (Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName)
    }
}

function ThenNodeModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )

    It ('should install the node module') {
        $expectedPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -Global
        $expectedPath | Should -Exist
        $taskParameter[$pathParameterName] | Should -Be $expectedPath

        if( $AtVersion )
        {
            Get-Content -Path (Join-Path -Path $expectedPath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version' | Should -Be $AtVersion
        }
    }
}

function ThenNodeModuleNotInstalled
{
    param(
        $Name
    )

    It ('should not install the node module') {
        $nodeModulesPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -Global -ErrorAction Ignore | Should -BeNullOrEmpty
        $nodeModulesPath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName -ErrorAction Ignore | Should -BeNullOrEmpty
        $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
    }
}

function ThenThrewException
{
    param(
        $Regex
    )

    It ('should throw an exception') {
        $threwException | Should -Be $true
        $Global:Error[0] | Should -Match $Regex
    }
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

Describe 'Install-WhiskeyTool.when installing Node and version defined by tool author' {
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

Describe 'Install-WhiskeyTool.when installing Node module and Node isn''t installed' {
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

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via version parameter' {
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

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via RequiresTool attribute''s Version property' {
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

Describe 'Install-WhiskeyTool.when installing .NET Core SDK' {
    Init
    Mock -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -MockWith { Join-Path -Path $InstallRoot -ChildPath '.dotnet\dotnet.exe' }
    GivenWorkingDirectory 'app'
    GivenVersionParameterName 'SdkVersion'
    WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' }
    ThenDotNetPathAddedToTaskParameter
    It 'should call Install-WhiskeyDotNetTool' {
        Assert-MockCalled -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $InstallRoot -eq $TestDrive.FullName -and `
            $WorkingDirectory -eq $taskWorkingDirectory -and `
            $version -eq '2.1.4'
        }
    }
}

Describe 'Install-WhiskeyTool.when .NET Core SDK fails to install' {
    Init
    Mock -CommandName 'Install-WhiskeyDotNetTool' -ModuleName 'Whiskey' -MockWith { Write-Error -Message 'Failed to install .NET Core SDK' }
    GivenVersionParameterName 'SdkVersion'
    WhenInstallingTool 'DotNet' @{ 'SdkVersion' = '2.1.4' } -ErrorAction SilentlyContinue
    ThenThrewException 'Failed\ to\ install\ .NET\ Core\ SDK'
}

function ThenDirectory
{
    param(
        $Path,
        [Switch]
        $Not,
        [Switch]
        $Exists
    )

    if( $Not )
    {
        It ('should not install') {
            Join-Path -Path $TestDRive.FullName -ChildPath $Path | Should -Not -Exist
        }
    }
    else
    {
        It ('should install') {
            Join-Path -Path $TestDRive.FullName -ChildPath $Path | Should -Exist
        }
    }
}

Describe 'Install-WhiskeyTool.when installing a PowerShell module' {
    Init
    GivenVersionParameterName 'Version'
    WhenInstallingTool 'PowerShellModule::Zip' -Parameter @{ 'Version' = '0.2.0' }
    ThenDirectory 'PSModules\Zip' -Exists
    $job = Start-Job { Import-Module -Name (Join-Path -Path $using:TestDrive.FullName -ChildPath 'PSModules\Zip') -PassThru }
    $moduleInfo = $job | Wait-Job | Receive-Job
    It ('should install requested version') {
        $moduleInfo.Version | Should -Be '0.2.0'
    }
}

Describe 'Install-WhiskeyTool.when failing to install a PowerShell module' {
    Init
    GivenVersionParameterName 'Version'
    WhenInstallingTool 'PowerShellModule::jfklfjsiomklmslkfs' -ErrorAction SilentlyContinue
    ThenDirectory 'PSModules\Whiskey' -Not -Exists
    ThenThrewException -Regex 'Failed\ to\ find'
}

Describe 'Install-WhiskeyTool.when failing to install a NuGet Package' {
    Init
    WhenInstallingTool -Name 'NuGet::TROLOLOLO' -Version 'Version' -ErrorAction SilentlyContinue
    ThenDirectory -Regex 'Unable\ to\ find'
}

Describe 'Install-WhiskeyNuGetPackage.when NuGet is the provider' {
    Init
    Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
    WhenInstallingTool 'NuGet::Nunit.Runners'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
    }
}

Describe 'Install-WhiskeyTool.when NuGet is the provider and version specified' {
    Init
    Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
    WhenInstallingTool 'NuGet::Nunit.Runners' -Version '2.6.4'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Version -eq '2.6.4'}
    }
}

Describe 'Install-WhiskeyTool.when NuGet is the provider' {
    Init
    Mock -CommandName 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey'
    WhenInstallingTool 'NuGet::Nunit.Runners' -Parameter @{ 'Version' = '2.6.4' } -Version '2.6.3'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Name -eq 'Nunit.Runners'}
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$DownloadRoot -eq $TestDrive.FullName}
        Assert-MockCalled 'Install-WhiskeyNuGetPackage' -ModuleName 'Whiskey' -ParameterFilter {$Version -eq '2.6.4'}
    }
}