
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$force = $false
$name = $null
$testRoot = $null

# Private Whiskey function. Define it so Pester doesn't complain about it not existing.
function Remove-WhiskeyFileSystemItem
{
}

function Init
{
    $Global:Error.Clear()
    $script:testRoot = New-WhiskeyTestRoot
    $script:name = $null
    $script:force = $false
    CreatePackageJson
    Install-Node -BuildRoot $script:testRoot
}

function CreatePackageJson
{
    $packageJsonPath = Join-Path -Path $script:testRoot -ChildPath 'package.json'

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
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey'
}

function GivenFailingRemoveItem
{
    Mock -CommandName 'Remove-WhiskeyFileSystemItem' -ModuleName 'Whiskey'
}

function GivenInstalledModule
{
    param(
        $Name
    )

    Push-Location $script:testRoot
    try
    {
        $parameter = @{
            'Name' = $Name;
            'BuildRootPath' = $script:testRoot;
        }
        Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNodeModule' -Parameter $parameter | Out-Null
    }
    finally
    {
        Pop-Location
    }
}

function Reset
{
}

function WhenUninstallingNodeModule
{
    [CmdletBinding()]
    param()
    
    $parameter = $PSBoundParameters
    $parameter['Name'] = $name
    $parameter['BuildRootPath'] = $script:testRoot
    $parameter['Force'] = $force

    Push-Location $script:testRoot
    try
    {
        Invoke-WhiskeyPrivateCommand -Name 'Uninstall-WhiskeyNodeModule' -Parameter $parameter
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
        [String]$Name,

        [Parameter(Mandatory,ParameterSetName='Exists')]
        [switch]$Exists,

        [Parameter(Mandatory,ParameterSetName='DoesNotExist')]
        [switch]$DoesNotExist
    )

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:testRoot -ErrorAction Ignore

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
    AfterEach { Reset }
    It 'should not fail' {
        Init
        GivenName 'wrappy'
        WhenUninstallingNodeModule
        ThenNoErrorsWritten
        ThenModule 'wrappy' -DoesNotExist
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when uninstalling an installed module' {
    AfterEach { Reset }
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
    AfterEach { Reset }
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
    AfterEach { Reset }
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
    AfterEach { Reset }
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
