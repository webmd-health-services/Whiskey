
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyNpmCommand.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Get-WhiskeyNPMPath.ps1' -Resolve)


$registryUri = 'http://registry.npmjs.org'
$applicationRoot = $null
$argument = @{}
$dependency = $null
$devDependency = $null
$npmCommand = $null
$nodeVersion = '^4.4.7'

function Init
{
    $Global:Error.Clear()
    $script:applicationRoot = $TestDrive.FullName
    $script:dependency = $null
    $script:devDependency = $null
    $script:argument = @{}
    $script:command = $null
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
    },
    "dependencies": {
        $($script:dependency -join ',')
    }
} 
"@ | Set-Content -Path $packageJsonPath -Force
}

function GivenArgument
{
    param(
        $Argument
    )
    $script:argument = @{ 'Argument' = $Argument }
}

function GivenDependency 
{
    param(
        [object[]]
        $Dependency 
    )
    $script:dependency = $Dependency
}

function GivenDevDependency 
{
    param(
        [object[]]
        $DevDependency 
    )
    $script:devDependency = $DevDependency
}

function GivenNpmCommand
{
    param(
        $Command
    )
    $script:npmCommand = $Command
}

function GivenFailingNodeJsInstall
{
    Mock -CommandName 'Install-WhiskeyNodeJs'
}

function GivenFailingNPMInstall
{
    Mock -CommandName 'Get-WhiskeyNPMPath'
}

function GivenMissingGlobalNPM
{
    Mock -CommandName 'Join-Path' -ParameterFilter { $ChildPath -eq 'node_modules\npm\bin\npm-cli.js' }
}

function WhenRunningNpmCommand
{
    [CmdletBinding()]
    param()

    CreatePackageJson

    Invoke-WhiskeyNpmCommand -NpmCommand $npmCommand -ApplicationRoot $applicationRoot -RegistryUri $registryUri @argument
}

function ThenErrorMessage
{
    param(
        $ErrorMessage
    )

    It ('should write error message [{0}]' -f $ErrorMessage) {
        $Global:Error[0] | Should -Match $ErrorMessage
    }
}

function ThenNoErrorsWritten
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenPackage
{
    param(
        [Parameter(Position=0)]
        [string]
        $PackageName,
        
        [Parameter(Mandatory=$true,ParameterSetName='Exists')]
        [switch]
        $Exists,

        [Parameter(Mandatory=$true,ParameterSetName='DoesNotExist')]
        [switch]
        $DoesNotExist
    )

    $packagePath = Join-Path -Path $script:applicationRoot -ChildPath ('node_modules\{0}' -f $PackageName)

    If ($Exists)
    {
        It ('should install package ''{0}''' -f $PackageName) {
            $packagePath | Should -Exist
        }
    }
    else
    {
        It ('should not install package ''{0}''' -f $PackageName) {
            $packagePath | Should -Not -Exist
        }
    }
}

function ThenExitCode
{
    param(
        $ExitCode
    )

    It ('should return exit code ''{0}''' -f $ExitCode) {
        $Global:LASTEXITCODE | Should -Be $ExitCode
    }
}

Describe 'Invoke-WhiskeyNpmCommand.when Node.js fails to install' {
    Init
    GivenNpmCommand 'install'
    GivenFailingNodeJsInstall
    WhenRunningNpmCommand -ErrorAction SilentlyContinue
    ThenErrorMessage 'Node.js version required for this package failed to install.'
    ThenExitCode 1
}

Describe 'Invoke-WhiskeyNpmCommand.when NPM is missing from global Node.js install' {
    Init
    GivenNpmCommand 'install'
    GivenMissingGlobalNPM
    WhenRunningNpmCommand -ErrorAction SilentlyContinue
    ThenErrorMessage 'NPM didn''t get installed by NVM when installing Node.'
    ThenExitCode 2
}

Describe 'Invoke-WhiskeyNpmCommand.when NPM fails to install' {
    Init
    GivenNpmCommand 'install'
    GivenFailingNPMInstall
    WhenRunningNpmCommand -ErrorAction SilentlyContinue
    ThenErrorMessage 'Could not locate version of NPM that is required for this package.'
    ThenExitCode 3
}

Describe 'Invoke-WhiskeyNpmCommand.when running successful NPM command' {
    Init
    GivenDependency '"wrappy": "^1.0.2"'
    GivenDevDependency '"pify": "^3.0.0"'
    GivenNpmCommand 'install'
    GivenArgument '--production'
    WhenRunningNpmCommand
    Thenpackage 'wrappy' -Exists
    ThenPackage 'pify' -DoesNotExist
    ThenExitCode 0
    ThenNoErrorsWritten
}

Describe 'Invoke-WhiskeyNpmCommand.when NPM command with argument that fails' {
    Init
    GivenNpmCommand 'install'
    GivenArgument 'fakepackage'
    WhenRunningNpmCommand -ErrorAction SilentlyContinue
    ThenExitCode 1
}
