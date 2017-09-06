
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Get-WhiskeyNPMPath.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeJs.ps1' -Resolve)

$buildRoot = $null
$failed = $false
$nodePath = $null
$npmPath = $null

function Get-BuildRoot
{
   $buildRoot = (Join-Path -Path $TestDrive.FullName -ChildPath 'BuildRoot')
   New-Item -Path $buildRoot -ItemType 'Directory' -Force | Out-Null

   return $buildRoot
}

function init
{
    $Global:Error.Clear()
    $script:buildRoot = (Get-BuildRoot)
    $script:failed = $false
    $script:nodePath = $null
    $script:npmPath = $null
}

function GivenNoNPMVersion
{
    GivenPackageJson
}

function GivenNPMVersion
{
    param(
        $NPMVersion
    )

    GivenPackageJson $NPMVersion
}

function GivenPackageJson
{
    param(
        $NPMVersion
    )

    $npmEngine = ''
    if ($NPMVersion)
    {
        $npmEngine = '"npm": "{0}",' -f $NPMVersion
    }

    $packageJson = @"
{
    "name": "npmtest",
    "version": "0.0.1",
    "description": "Get-WhiskeyNPMPath test app",
    "main": "main.js",
    "engines": { 
        $npmEngine
        "node": "4.4.7" 
    },
    "license": "MIT",
    "repository": "bitbucket:example/repo"
}
"@

    Set-Content -Path (Join-Path -Path $buildRoot -ChildPath 'package.json') -Value $packageJson -Force
}

function WhenGettingNPMPath
{
    Push-Location $buildRoot

    $script:nodePath = Install-WhiskeyNodeJs -RegistryUri 'http://registry.npmjs.org/' -ApplicationRoot $buildRoot
    $script:npmPath = Get-WhiskeyNPMPath -ApplicationRoot $buildRoot -NodePath $nodePath -ErrorAction SilentlyContinue

    Pop-Location
}

function ThenNPMPathIsGlobal
{
    It 'npm path should be the global version that comes with nvm' {
        $script:npmPath | Should -Be (Join-Path -Path $env:NVM_HOME -ChildPath 'v4.4.7\node_modules\npm\bin\npm-cli.js')
    }
}

function ThenNPMPathIsLocal
{
    It 'npm path should be in local ''node_modules'' directory' {
        $script:npmPath | Should -Be (Join-Path -Path $buildRoot -ChildPath 'node_modules\npm\bin\npm-cli.js')
    }
}

function ThenNPMShouldBeVersion
{
    param(
        $NPMVersion
    )

    $npmInstalledVersion = & $nodePath $npmPath '--version'

    It ('npm should be version ''{0}''' -f $NPMVersion) {
        $npmInstalledVersion | Should -Be $NPMVersion
    }
}

function ThenErrorMessage
{
    param(
        $Message
    )

    It ('error message should match ''{0}''' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

Describe 'Get-WhiskeyNPMPath.when no NPM version is specified in package.json' {
    Init
    GivenNoNPMVersion
    WhenGettingNPMPath
    ThenNPMPathIsGlobal
}

Describe 'Get-WhiskeyNPMPath.when specific version of NPM is set in package.json' {
    Init
    GivenNPMVersion '5.1.0'
    WhenGettingNPMPath
    ThenNPMPathIsLocal
    ThenNPMShouldBeVersion '5.1.0'

    # npm module path in TestDrive is too long for Pester to cleanup with Remove-Item
    & cmd /C rmdir /S /Q (Join-Path -Path (Get-BuildRoot) -ChildPath 'node_modules')
}

Describe 'Get-WhiskeyNPMPath.when NPM version in package.json is not a semantic version' {
    Init
    GivenNPMVersion '5'
    WhenGettingNPMPath
    ThenErrorMessage 'NPM version ''5'' is invalid.'
}