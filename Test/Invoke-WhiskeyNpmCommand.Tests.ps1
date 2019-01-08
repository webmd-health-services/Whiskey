
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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
    Install-Node
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
    Mock -CommandName 'Join-Path' -ParameterFilter { $ChildPath -eq 'node_modules\npm\bin\npm-cli.js' }
}

function WhenRunningNpmCommand
{
    [CmdletBinding()]
    param()

    CreatePackageJson
    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $TestDrive.FullName
    Push-Location $TestDrive.FullName
    try
    {
        Invoke-WhiskeyNpmCommand -Name $npmCommand @argument -NodePath $nodePath 
    }
    finally
    {
        Pop-Location
    }
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
        $Global:Error | 
            Where-Object { $_ -notmatch '\bnpm\ (notice|warn)\b' } | 
            Should -BeNullOrEmpty
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

    $packagePath = Join-Path -Path $TestDrive.FullName -ChildPath ('node_modules\{0}' -f $PackageName)

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

function ThenNpmNotRun
{
    It 'should not run npm' {
        Assert-MockCalled -CommandName 'Invoke-Command' -Times 0
    }
}


Describe 'Invoke-WhiskeyNpmCommand.when running successful NPM command' {
    try
    {
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
    finally
    {
        Remove-Node
    }
}

Describe 'Invoke-WhiskeyNpmCommand.when NPM command with argument that fails' {
    try
    {
        Init
        GivenNpmCommand 'install'
        GivenArgument 'thisisanonexistentpackage'
        WhenRunningNpmCommand
        ThenExitCode 1
        It ('should not stop because of NPM STDERR') {
            $Global:Error | 
                Where-Object { $_ -match 'failed\ with\ exit\ code' } | 
                Should -Not -BeNullOrEmpty
        }
    }
    finally
    {
        Remove-Node
    }
}
