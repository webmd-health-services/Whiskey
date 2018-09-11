
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$output = $null
$version = $null

function Init
{
    param(
    )

    $script:dependency = $null
    $script:devDependency = $null
    $Global:Error.Clear()
    $script:failed = $false
    $script:output = $null
    $script:version = $null
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
    },
    "devDependencies": {
        $($script:devDependency -join ',')
    }
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

function GivenVersion
{
    param(
        $WithVersion
    )

    $script:version = $WithVersion
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    $taskParameter['NpmVersion'] = '>=6'

    try
    {
        CreatePackageJson

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmInstall'
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmAudit'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It ('error message should match [{0}]' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenTaskSucceeded
{
    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NpmAudit.when dependency has a security vulnerability' {
    try
    {
        Init
        GivenDependency '"minimatch": "3.0.0"'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'npm\ audit\b.*\bfailed\ with\ exit\ code\ \d+'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmAudit.when dev dependency has a security vulnerability' {
    try
    {
        Init
        GivenDevDependency '"minimatch": "3.0.0"'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'npm\ audit\b.*\bfailed\ with\ exit\ code\ \d+'
    }
    finally
    {
        Remove-Node
    }
}
