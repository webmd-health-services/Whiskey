
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Install-WhiskeyNodeModule.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyNpmCommand.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Get-WhiskeyNPMPath.ps1' -Resolve)

$applicationRoot = $null
$name = $null
$nodeVersion = '^4.4.7'
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
}

function GivenModuleNotFound
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ParameterFilter { $NpmCommand -eq 'install' } -MockWith { & cmd /c exit 0 }
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
    "license": "MIT",
    "engines": {
        "node": "$nodeVersion"
    }
} 
"@ | Set-Content -Path $packageJsonPath -Force
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
    $script:output = Install-WhiskeyNodeModule -Name $name -ApplicationRoot $applicationRoot -RegistryUri $registryUri @versionParam
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
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenReturnedPathForModule
{
    param(
        $Module
    )

    $modulePath = Join-Path -Path $applicationRoot -ChildPath ('node_modules\{0}' -f $Module)
    
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
    Init
    GivenName 'wrappy'
    WhenInstallingNodeModule
    ThenModule 'wrappy' -Exists
    ThenReturnedPathForModule 'wrappy'
    ThenNoErrorsWritten
}

Describe 'Install-WhiskeyNodeModule.when given name and version' {
    Init
    GivenName 'wrappy'
    GivenVersion '1.0.2'
    WhenInstallingNodeModule
    ThenModule 'wrappy' -Version '1.0.2' -Exists
    ThenReturnedPathForModule 'wrappy'
    ThenNoErrorsWritten
}

Describe 'Install-WhiskeyNodeModule.when given bad module name' {
    Init
    GivenName 'nonexistentmodule'
    WhenInstallingNodeModule -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorMessage 'Failed to install Node module ''nonexistentmodule''.'
}

Describe 'Install-WhiskeyNodeModule.when NPM executes successfully but module is not found' {
    Init
    GivenName 'wrappy'
    GivenModuleNotFound
    WhenInstallingNodeModule -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorMessage 'NPM executed successfully when attempting to install ''wrappy'' but the module was not found'
}