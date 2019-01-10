
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNode.ps1' -Resolve)

$threwException = $false
$taskWorkingDirectory = $null
$nodePath = $null

function GivenPackageJson
{
    param(
        $InputObject,
        $InDirectory = $TestDrive.FullName
    )

    $InputObject | Set-Content -Path (Join-Path -Path $InDirectory -ChildPath 'package.json')
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
    $script:nodePath = $null
    $script:threwException = $false
    $script:taskWorkingDirectory = $TestDrive.FullName
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

    It ('should return path to node executable') {
        $nodePath | Should -Be (Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName)
    }
}

function ThenNodeNotInstalled
{
    It ('should not install Node') {
        Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    $npmPath = Join-Path -Path $TestDRive.FullName -ChildPath '.node\node_modules\npm\bin\npm-cli.js'
    It ('should not install NPM') {
        $npmPath | Should -Not -Exist
    }

    It ('should not set path to node') {
        $nodePath | Should -BeNullOrEmpty
    }
}

function ThenNodePackageNotFound
{
    It ('should report failure to download') {
        $Error[0] | Should -Match 'NotFound'
    }
}

function ThenNoError
{
    It ('should not write any errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenNothingReturned
{
    It ('should return nothing') {
        $nodePath | Should -BeNullOrEmpty
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
        $Version,
        [Switch]
        $InCleanMode
    )

    $Global:Error.Clear()

    $optionalParams = @{}
    if( $Version )
    {
        $optionalParams['Version'] = $Version
    }

    if( $InCleanMode )
    {
        $optionalParams['InCleanMode'] = $InCleanMode
    }

    Push-Location -path $taskWorkingDirectory
    try
    {
        $script:nodePath = Install-WhiskeyNode -InstallRoot $TestDrive.FullName @optionalParams
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

Describe 'Install-WhiskeyNode.when installing' {
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

Describe 'Install-WhiskeyNode.when installing old version' {
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

Describe 'Install-WhiskeyNode.when installing specific version' {
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

Describe 'Install-WhiskeyNode.when upgrading to a new version' {
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

Describe 'Install-WhiskeyNode.when user specifies version in whiskey.yml and uses wildcard' {
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
        WhenInstallingTool 'Node' -Version '8.8.*'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyNode.when using custom version of NPM' {
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

Describe 'Install-WhiskeyNode.when already installed' {
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

Describe 'Install-WhiskeyNode.when package.json is in working directory' {
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

Describe 'Install-WhiskeyNode.when run in clean mode' {
    try
    {
        Init
        WhenInstallingTool 'Node' -InCleanMode
        ThenNodeNotInstalled
        ThenNoError
        ThenNothingReturned
    }
    finally
    {
        Remove-Node
    }
}


Describe 'Install-WhiskeyNode.when run in clean mode and Node is installed' {
    try
    {
        Init
        Install-Node
        WhenInstallingTool 'Node' -InCleanMode
        ThenNodeInstalled -AtLatestVersion
        ThenNoError
    }
    finally
    {
        Remove-Node
    }
}

