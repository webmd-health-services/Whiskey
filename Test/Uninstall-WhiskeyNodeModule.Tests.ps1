
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Uninstall-WhiskeyNodeModule.ps1' -Resolve)

$applicationRoot = $null
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
    Mock -CommandName 'Remove-Item'
}

function GivenInstalledModule
{
    param(
        $Name
    )

    Push-Location $TestDrive.FullName
    try
    {
        Install-WhiskeyNodeModule -Name $Name -NodePath (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe') -ApplicationRoot $applicationRoot | Out-Null
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
        Uninstall-WhiskeyNodeModule -Name $name -ApplicationRoot $applicationRoot -RegistryUri $registryUri -Force:$force
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
        $Global:Error | Where-Object { $_ -notmatch '\bnpm (notice|warn)\b' } | Should -BeNullOrEmpty
    }
}

function ThenErrorMessage
{
    param(
        $Message
    )

    It ('error message should match [{0}]' -f $Message) {
        $Global:Error | Should -Match $Message
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given module is not installed' {
    try
    {
        Init
        GivenName 'wrappy'
        WhenUninstallingNodeModule
        ThenNoErrorsWritten
        ThenModule 'wrappy' -DoesNotExist
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when uninstalling an installed module' {
    try
    {
        Init
        GivenInstalledModule 'wrappy'
        GivenInstalledModule 'pify'
        GivenName 'wrappy'
        WhenUninstallingNodeModule
        ThenModule 'wrappy' -DoesNotExist
        ThenModule 'pify' -Exists
        ThenNoErrorsWritten
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and npm uninstall fails to remove module' {
    try
    {
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
    finally
    {
        Remove-Node
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when npm uninstall fails to remove module' {
    try
    {
        Init
        GivenInstalledModule 'wrappy'
        GivenName 'wrappy'
        GivenFailingNpmUninstall
        WhenUninstallingNodeModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to remove Node module ''wrappy'''
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Uninstall-WhiskeyNodeModule.when given Force and manual removal fails' {
    try
    {
        Init
        GivenInstalledModule 'wrappy'
        GivenName 'wrappy'
        GivenForce
        GivenFailingNpmUninstall
        GivenFailingRemoveItem
        WhenUninstallingNodeModule -ErrorAction SilentlyContinue
        ThenErrorMessage 'Failed to remove Node module ''wrappy'''
    }
    finally
    {
        Remove-Node
    }
}
