
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeModule.ps1' -Resolve)

$name = $null
$output = $null
$registryUri = 'http://registry.npmjs.org'
$version = $null

function Init
{
    $Global:Error.Clear()
    $script:applicationRoot = $TestDrive.FullName
    $script:name = $null
    $script:output = $null
    $script:version = $null
    Install-Node
}

function GivenModuleNotFound
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ParameterFilter { if( $ErrorActionPreference -ne 'Stop' ) { throw 'Must pass -ErrorAction Stop as a parameter to Invoke-WhiskeyNpmCommand.' } return $true }
}

function GivenName
{
    param(
        $Module
    )
    $script:name = $Module
}

function GivenVersion
{
    param(
        $Version
    )
    $script:version = $Version
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

function WhenInstallingNodeModule
{
    [CmdletBinding()]
    param()
    
    CreatePackageJson

    $versionParam = @{}
    if ($version)
    {
        $versionParam['Version'] = $version
    }

    Push-Location $TestDrive.FullName
    try
    {
        $script:output = Install-WhiskeyNodeModule -Name $name @versionParam -NodePath (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe')
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

        [Parameter(Mandatory=$false,ParameterSetName='Exists')]
        [string]
        $Version,
        
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
        It ('should install module ''{0}''' -f $Name) {
            $modulePath | Should -Exist
        }

        if ($Version)
        {
            $moduleVersion = Get-Content -Path (Join-Path -Path $modulePath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'Version'
            It ('module should be version {0}' -f $Version) {
                $moduleVersion | Should -Be $Version
            }
        }
    }
    else
    {
        It ('should not install module ''{0}''' -f $Name) {
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
        $Global:Error | Where-Object { $_ -match $Message } | Should -Not -BeNullOrEmpty
    }
}

function ThenReturnedPathForModule
{
    param(
        $Module
    )

    $modulePath = Join-Path -Path $TestDrive.FullName -ChildPath ('node_modules\{0}' -f $Module)
    
    It 'should return the path to the module' {
        $output | Should -Be $modulePath
    }
}

function ThenReturnedNothing
{
    It 'should return nothing' {
        $output | Should -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyNodeModule.when given name' {
    try
    {
        Init
        GivenName 'wrappy'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyNodeModule.when given name and version' {
    try
    {
        Init
        GivenName 'wrappy'
        GivenVersion '1.0.2'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Version '1.0.2' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyNodeModule.when given bad module name' {
    try
    {
        Init
        GivenName 'nonexistentmodule'
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'failed\ with\ exit\ code\ 1'
        It ('should not report NPM finished successfully') {
            $Global:Error | Where-Object { $_ -match 'NPM\ executed\ successfully' } | Should -BeNullOrEmpty
        }
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyNodeModule.when NPM executes successfully but module is not found' {
    try
    {
        Init
        GivenName 'wrappy'
        GivenModuleNotFound
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'NPM executed successfully when attempting to install ''wrappy'' but the module was not found'
    }
    finally
    {
        Remove-Node
    }
}