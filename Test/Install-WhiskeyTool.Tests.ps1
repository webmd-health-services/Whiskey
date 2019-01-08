
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Invoke-NuGetInstall
{
    [CmdletBinding()]
    param(
        $Package,
        $Version,

        [switch]
        $invalidPackage
    )

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName $Package -Version $Version
    if( -not $invalidPackage)
    {
        Context 'the NuGet Package' {
            It 'should exist' {
                $result | Should -Exist
            }
            It 'should get installed into $DownloadRoot\packages' {
                $result | Should -BeLike ('{0}\packages\*' -f $TestDrive.FullName)
            }
        }
    }
    else
    {
        Context 'the Invalid NuGet Package' {
            It 'should NOT exist' {
                $result | Should Not Exist
            }
            it 'should write errors' {
                $Global:Error | Should NOT BeNullOrEmpty
            }
        }
    }
}

Describe 'Install-WhiskeyTool.when given a NuGet Package' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version '2.6.4'
}

Describe 'Install-WhiskeyTool.when NuGet Pack is bad' {
    Invoke-NuGetInstall -package 'BadPackage' -version '1.0.1' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when NuGet pack Version is bad' {
    Invoke-NugetInstall -package 'Nunit.Runners' -version '0.0.0' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when given a NuGet Package with an empty version string' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version ''
}

Describe 'Install-WhiskeyTool.when installing an already installed NuGet package' {

    $Global:Error.Clear()

    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyTool.when set EnableNuGetPackageRestore' {
    Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName 'NUnit.Runners' -version '2.6.4'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
    }
}

$threwException = $false
$pathParameterName = 'ToolPath'
$versionParameterName = $null
$taskParameter = $null
$taskWorkingDirectory = $null

function GivenPackageJson
{
    param(
        $InputObject,
        $InDirectory = $TestDrive.FullName
    )

    $InputObject | Set-Content -Path (Join-Path -Path $InDirectory -ChildPath 'package.json')
}

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
    It ('should set path to the dotnet.exe') {
        $taskParameter[$pathParameterName] | Should -BeLike '*\dotnet.exe'
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

    It ('should download Node ZIP file') {
        Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node-{0}-win-x64.zip' -f $NodeVersion) | Should -Exist
    }

    It ('should install Node') {
        $nodePath | Should -Exist
        & $nodePath '--version' | Should -Be $NodeVersion
    }


    $npmPath = Join-Path -Path $TestDRive.FullName -ChildPath '.node\node_modules\npm\bin\npm-cli.js'
    It ('should install NPM') {
        $npmPath | Should -Exist
        & $nodePath $npmPath '--version' | Should -Be $NpmVersion
    }

    It ('should set path to node.exe') {
        $taskParameter[$pathParameterName] | Should -Be (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe')
    }
}

function ThenNodeModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )

    It ('should install the node module') {
        $expectedPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node_modules\{0}' -f $Name)
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
        $expectedPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node_modules\{0}' -f $Name)
        $expectedPath | Should -Not -Exist
        $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
    }
}

function ThenNodeNotInstalled
{
    $nodePath = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe'
    It ('should not install Node') {
        $nodePath | Should -Not -Exist
    }

    $npmPath = Join-Path -Path $TestDRive.FullName -ChildPath '.node\node_modules\npm\bin\npm-cli.js'
    It ('should not install NPM') {
        $npmPath | Should -Not -Exist
    }

    It ('should not set path to node') {
        $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
    }
}

function ThenNodePackageNotFound
{
    It ('should report failure to download') {
        $Error[0] | Should -Match 'NotFound'
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

Describe 'Install-WhiskeyTool.when installing Node' {
    try
    {
        Init
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing old version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "4.4.7"
    }
}
'@
        WhenInstallingTool 'Node' -ErrorAction SilentlyContinue
        ThenThrewException 'Failed to download Node v4\.4\.7'
        ThenNodeNotInstalled
        ThenNodePackageNotFound
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "9.2.1"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v9.2.1' -NpmVersion '5.5.1'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when upgrading to a new version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.8.1"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v8.9.0' -NpmVersion '5.6.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when user specifies version of Node in whiskey.yml and uses wildcard' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        GivenVersionParameterName 'Fubar'
        WhenInstallingTool 'Node' @{ 'Fubar' = '8.8.*' }
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when task author specifies version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node' @{  } -Version '8.8.*'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when using custom version of NPM' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion -NpmVersion '5.6.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when already installed' {
    try
    {
        Init
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion

        Mock -CommandName 'Invoke-WebRequest' -Module 'Whiskey'
        $nodeUnzipPath = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node-*-win-x64'
        Get-ChildItem -Path $nodeUnzipPath -Directory | Remove-Item
        WhenInstallingTool 'Node'
        It ('should not re-unzip ZIP file') {
            $nodeUnzipPath | Should -Not -Exist
        }
        It 'should not re-download Node' {
            Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
        }
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when package.json is in working directory' {
    try
    {
        Init
        GivenWorkingDirectory 'app'

        # Put a package.json in the root to ensure package.json in the current directory is used first.
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.4"
    }
}
'@

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0"
    }
}
'@ -InDirectory $taskWorkingDirectory

        WhenInstallingTool 'Node'
        ThenNodeInstalled -NodeVersion 'v8.9.0' -NpmVersion '5.5.1'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing Node module' {
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
    WhenInstallingTool 'PowerShellModule::Whiskey' -Parameter @{ 'Version' = '0.37.1' }
    ThenDirectory 'PSModules\Whiskey' -Exists
    $job = Start-Job { Import-Module -Name (Join-Path -Path $using:TestDrive.FullName -ChildPath 'PSModules\Whiskey') -PassThru }
    $moduleInfo = $job | Wait-Job | Receive-Job
    It ('should install requested version') {
        $moduleInfo.Version | Should -Be '0.37.1'
    }
}

Describe 'Install-WhiskeyTool.when failing to install a PowerShell module' {
    Init
    GivenVersionParameterName 'Version'
    WhenInstallingTool 'PowerShellModule::jfklfjsiomklmslkfs' -ErrorAction SilentlyContinue
    ThenDirectory 'PSModules\Whiskey' -Not -Exists
    ThenThrewException -Regex 'Failed\ to\ find'
}