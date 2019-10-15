
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$argument = @{}
$dependency = $null
$devDependency = $null
$npmCommand = $null

function Init
{
    $Global:Error.Clear()
    $script:argument = @{}
    $script:command = $null
    $script:dependency = $null
    $script:devDependency = $null

    $script:testRoot = New-WhiskeyTestRoot

    Install-Node -BuildRoot $testRoot
}

function CreatePackageJson
{
    $packageJsonPath = Join-Path -Path $testRoot -ChildPath 'package.json'

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "description": "test",
    "repository": "bitbucket:example/repo",
    "private": true,
    "license": "MIT",
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
    $script:argument = @{ 'ArgumentList' = $Argument }
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

function GivenMissingGlobalNPM
{
    Mock -CommandName 'Join-Path' -ParameterFilter { $ChildPath -eq 'bin\npm-cli.js' }
}

function Reset
{
    Remove-Node -BuildRoot $testRoot
}

function ThenErrorMessage
{
    param(
        $ErrorMessage
    )

    $Global:Error[0] | Should -Match $ErrorMessage
}

function ThenNoErrorsWritten
{
    $Global:Error | 
        Where-Object { $_ -notmatch '\bnpm\ (notice|warn)\b' } | 
        Should -BeNullOrEmpty
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

    $packagePath = Resolve-WhiskeyNodeModulePath -Name $PackageName -BuildRootPath $testRoot -ErrorAction Ignore

    If ($Exists)
    {
        $packagePath | Should -Not -BeNullOrEmpty
        $packagePath | Should -Exist
    }
    else
    {
        $packagePath | Should -BeNullOrEmpty
    }
}

function ThenExitCode
{
    param(
        $ExitCode
    )

    $Global:LASTEXITCODE | Should -Be $ExitCode
}

function ThenNpmNotRun
{
    Assert-MockCalled -CommandName 'Invoke-Command' -Times 0
}

function WhenRunningNpmCommand
{
    [CmdletBinding()]
    param()

    CreatePackageJson
    Push-Location $testRoot
    try
    {
        Invoke-WhiskeyNpmCommand -Name $npmCommand @argument -BuildRootPath $testRoot
    }
    finally
    {
        Pop-Location
    }
}

Describe 'Invoke-WhiskeyNpmCommand.when running successful NPM command' {
    AfterEach { Reset }
    It 'should pass build' {
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
}

Describe 'Invoke-WhiskeyNpmCommand.when NPM command with argument that fails' {
    AfterEach { Reset }
    It 'should fail build' {
        Init
        GivenNpmCommand 'install'
        GivenArgument 'thisisanonexistentpackage'
        WhenRunningNpmCommand
        ThenExitCode 1
        $Global:Error | 
            Where-Object { $_ -match 'failed\ with\ exit\ code' } | 
            Should -Not -BeNullOrEmpty
    }
}
