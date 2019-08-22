
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
    $script:name = $null
    $script:output = $null
    $script:version = $null
    Install-Node
}

function GivenNpmSucceedsButModuleNotInstalled
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -MockWith $SuccessCommandScriptBlock
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
    $packageJsonPath = Join-Path -Path $TestDrive.FullName -ChildPath 'package.json'

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
        $script:output = Install-WhiskeyNodeModule -Name $name @versionParam -BuildRootPath $TestDrive.FullName
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

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $TestDrive.FullName

    if ($Exists)
    {
        $modulePath | Should -Exist

        if ($Version)
        {
            $moduleVersion = Get-Content -Path (Join-Path -Path $modulePath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'Version'
            $moduleVersion | Should -Be $Version
        }
    }
    else
    {
        $modulePath | Should -Not -Exist
    }
}

function ThenNoErrorsWritten
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenErrorMessage
{
    param(
        $Message
    )

    $Global:Error | Where-Object { $_ -match $Message } | Should -Not -BeNullOrEmpty
}

function ThenReturnedPathForModule
{
    param(
        $Module
    )

    $modulePath = Resolve-WhiskeyNodeModulePath -Name $Module -BuildRootPath $TestDrive.FullName
    
    $output | Should -Be $modulePath
}

function ThenReturnedNothing
{
    $output | Should -BeNullOrEmpty
}

Describe 'Install-WhiskeyNodeModule.when given name' {
    AfterEach { Remove-Node }
    It 'should install the module' {
        Init
        GivenName 'wrappy'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }
}

Describe 'Install-WhiskeyNodeModule.when given name and version' {
    AfterEach { Remove-Node }
    It 'should install that version' {
        Init
        GivenName 'wrappy'
        GivenVersion '1.0.2'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Version '1.0.2' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }
}

Describe 'Install-WhiskeyNodeModule.when given bad module name' {
    AfterEach { Remove-Node }
    It 'should fail' {
        Init
        GivenName 'nonexistentmodule'
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'failed\ with\ exit\ code\ 1'
        $Global:Error | Where-Object { $_ -match 'NPM\ executed\ successfully' } | Should -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyNodeModule.when NPM executes successfully but module is not found' {
    AfterEach { Remove-Node }
    It 'should fail' {
        Init
        GivenName 'wrappy'
        GivenNpmSucceedsButModuleNotInstalled
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'NPM executed successfully when attempting to install "wrappy" but the module was not found'
    }
}