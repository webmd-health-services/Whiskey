
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Uninstall-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyNpmCommand.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyRobocopy.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Get-WhiskeyNPMPath.ps1' -Resolve)

$applicationRoot = $null
$force = $false
$name = $null
$nodeVersion = '^4.4.7'
$registryUri = 'http://registry.npmjs.org'

function Init
{
    $Global:Error.Clear()
    $script:applicationRoot = $TestDrive.FullName
    $script:name = $null
    $script:force = $false

    CreatePackageJson
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
    "license": "MIT",
    "engines": {
        "node": "$nodeVersion"
    }
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

function GivenFailingNpmPrune
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ParameterFilter { $NpmCommand -eq 'prune' }
}

function GivenFailingRemoveItem
{
    Mock -CommandName 'Remove-Item'
}

function GivenInstalledModule
{
    param(
        $Name
    )

    Install-WhiskeyNodeModule -Name $Name -ApplicationRoot $applicationRoot -RegistryUri $registryUri | Out-Null
}

function WhenUninstallingNodeModule
{
    [CmdletBinding()]
    param()
    
    Uninstall-WhiskeyNodeModule -Name $name -ApplicationRoot $applicationRoot -RegistryUri $registryUri -Force:$force
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

    $modulePath = Join-Path -Path $script:applicationRoot -ChildPath ('node_modules\{0}' -f $Name)

    if ($Exists)
    {
        It ('should not remove module ''{0}''' -f $Name) {
            $modulePath | Should -Exist
        }

    }
    else
    {
        It ('should remove module ''{0}''' -f $Name) {
            $modulePath | Should -Not -Exist
        }
    }
}

function ThenNoErrorsWritten
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenErrorMessage
{
    param(
        $Message
    )

    It ('error message should match [{0}]' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given module is not installed' {
    Init
    GivenName 'wrappy'
    WhenUninstallingNodeModule
    ThenNoErrorsWritten
}

Describe 'Uninstall-WhiskeyNodeModule.when given name' {
    Init
    GivenInstalledModule 'wrappy'
    GivenInstalledModule 'pify'
    GivenName 'wrappy'
    WhenUninstallingNodeModule
    ThenModule 'wrappy' -DoesNotExist
    ThenModule 'pify' -Exists
    ThenNoErrorsWritten
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and npm prune fails to remove module' {
    Init
    GivenInstalledModule 'wrappy'
    GivenInstalledModule 'pify'
    GivenName 'wrappy'
    GivenForce
    GivenFailingNpmPrune
    WhenUninstallingNodeModule -ErrorAction SilentlyContinue
    ThenModule 'wrappy' -DoesNotExist
    ThenModule 'pify' -Exists
    ThenNoErrorsWritten
}

Describe 'Uninstall-WhiskeyNodeModule.when npm prune fails to remove module' {
    Init
    GivenInstalledModule 'wrappy'
    GivenName 'wrappy'
    GivenFailingNpmPrune
    WhenUninstallingNodeModule -ErrorAction SilentlyContinue
    ThenErrorMessage 'Failed to remove Node module ''wrappy'''
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and manual removal fails' {
    Init
    GivenInstalledModule 'wrappy'
    GivenName 'wrappy'
    GivenForce
    GivenFailingNpmPrune
    GivenFailingRemoveItem
    WhenUninstallingNodeModule -ErrorAction SilentlyContinue
    ThenErrorMessage 'Failed to remove Node module ''wrappy'''
}
