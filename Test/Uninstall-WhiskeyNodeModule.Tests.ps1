
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Uninstall-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Remove-WhiskeyFileSystemItem.ps1' -Resolve)

$force = $false
$name = $null
$registryUri = 'http://registry.npmjs.org'

function Init
{
    $Global:Error.Clear()
    $script:applicationRoot = $TestDrive.FullName
    $script:name = $null
    $script:force = $false
    CreatePackageJson
    Install-Node
}

function CreatePackageJson
{
    $packageJsonPath = Join-Path -Path $script:applicationRoot -ChildPath 'package.json'

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "description": "test",
    "repository": "bitbucket:example/repo",
    "private": true,
    "license": "MIT"
} 
"@ | Set-Content -Path $packageJsonPath -Force

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "lockfileVersion": 1,
    "requires": true,
    "dependencies": {
    }
} 
"@ | Set-Content -Path ($packageJsonPath -replace '\bpackage\.json','package-lock.json') -Force
}

function GivenName
{
    param(
        $Module
    )
    $script:name = $Module
}

function GivenForce
{
    $script:force = $true
}

function GivenFailingNpmUninstall
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand'
}

function GivenFailingRemoveItem
{
    Mock -CommandName 'Remove-WhiskeyFileSystemItem'
}

function GivenInstalledModule
{
    param(
        $Name
    )

    Push-Location $TestDrive.FullName
    try
    {
        Install-WhiskeyNodeModule -Name $Name -BuildRootPath $TestDrive.FullName | Out-Null
    }
    finally
    {
        Pop-Location
    }
}

function WhenUninstallingNodeModule
{
    [CmdletBinding()]
    param()
    
    Push-Location $TestDrive.FullName
    try
    {
        Uninstall-WhiskeyNodeModule -Name $name -BuildRootPath $TestDrive.FullName -Force:$force
    }
    finally
    {
        Pop-Location
    }
}

function ThenModule
{
    param(
        [Parameter(Position=0)]
        [string]
        $Name,

        [Parameter(Mandatory=$true,ParameterSetName='Exists')]
        [switch]
        $Exists,

        [Parameter(Mandatory=$true,ParameterSetName='DoesNotExist')]
        [switch]
        $DoesNotExist
    )

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:applicationRoot -ErrorAction Ignore

    if ($Exists)
    {
        $modulePath | Should -Not -BeNullOrEmpty
    }
    else
    {
        $modulePath | Should -BeNullOrEmpty
    }
}

function ThenNoErrorsWritten
{
    $Global:Error | Where-Object { $_ -notmatch '\bnpm (notice|warn)\b' } | Should -BeNullOrEmpty
}

function ThenErrorMessage
{
    param(
        $Message
    )

    $Global:Error | Should -Match $Message
}

Describe 'Uninstall-WhiskeyNodeModule.when given module is not installed' {
    AfterEach { Remove-Node }
    It 'should not fail' {
        Init
        GivenName 'wrappy'
        WhenUninstallingNodeModule
        ThenNoErrorsWritten
        ThenModule 'wrappy' -DoesNotExist
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when uninstalling an installed module' {
    AfterEach { Remove-Node }
    It 'should remove the module' {
        Init
        GivenInstalledModule 'wrappy'
        GivenInstalledModule 'pify'
        GivenName 'wrappy'
        WhenUninstallingNodeModule
        ThenModule 'wrappy' -DoesNotExist
        ThenModule 'pify' -Exists
        ThenNoErrorsWritten
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and npm uninstall fails to remove module' {
    AfterEach { Remove-Node }
    It 'should ignore uninstall failures' {
        Init
        GivenInstalledModule 'wrappy'
        GivenInstalledModule 'pify'
        GivenName 'wrappy'
        GivenForce
        GivenFailingNpmUninstall
        WhenUninstallingNodeModule
        ThenModule 'wrappy' -DoesNotExist
        ThenModule 'pify' -Exists
        ThenNoErrorsWritten
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when npm uninstall fails to remove module' {
    AfterEach { Remove-Node }
    It 'should fail' {
        Init
        GivenInstalledModule 'wrappy'
        GivenName 'wrappy'
        GivenFailingNpmUninstall
        WhenUninstallingNodeModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to remove Node module "wrappy"'
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and manual removal fails' {
    AfterEach { Remove-Node }
    It 'should fail' {
        Init
        GivenInstalledModule 'wrappy'
        GivenName 'wrappy'
        GivenForce
        GivenFailingNpmUninstall
        GivenFailingRemoveItem
        WhenUninstallingNodeModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to remove Node module "wrappy"'
    }
}
