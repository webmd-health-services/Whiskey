
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$dependency = $null
$devDependency = $null
$failed = $false
$licenseReportPath = $null
$output = $null
$whsFailOn = @("--json", "--failOn", "AGPL-1.0-or-later;GPL-1.0-or-later;LGPL-2.0-or-later")

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:output = $null

    $script:testRoot = New-WhiskeyTestRoot

    Install-Node -BuildRoot $testRoot
}

function CreatePackageJson
{
    param(
        [String]$License
    )
    $packageJsonPath = Join-Path -Path $testRoot -ChildPath 'package.json'

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "description": "test",
    "repository": "bitbucket:example/repo",
    "private": false,
    "license": "$($License)",
    "dependencies": {
        $($script:dependency -join ',')
    },
    "devDependencies": {
        $($script:devDependency -join ',')
    }
} 
"@ | Set-Content -Path $packageJsonPath -Force
}

function GivenDependency 
{
    param(
        [Object[]]$Dependency 
    )
    $script:dependency = $Dependency
}

function GivenDevDependency 
{
    param(
        [Object[]]$DevDependency 
    )
    $script:devDependency = $DevDependency
}

function Reset
{
    Remove-Node -BuildRoot $testRoot
}

function ThenLicenseCheckerNotRun
{
    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match '--json' } -Times 0
}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    $failed | Should -BeTrue
    $Global:Error[0] | Should -Match $Message
}

function ThenTaskSucceeded
{
    # filter out the NPM Warn messages out of the error record
    $TaskErrors = $Global:Error | Where-Object { $_ -notmatch 'npm WARN' }
    $TaskErrors | Should -BeNullOrEmpty
    $failed | Should -BeFalse
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [String]$License,

        [String[]]$Argument
    )

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $testRoot

    $taskParameter = @{ }

    if( $Argument )
    {
        $taskParameter['Arguments'] = $Argument 
    }

    try
    {
        CreatePackageJson -license $License

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NodeLicenseChecker'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'NodeLicenseChecker.when running license-checker' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        WhenRunningTask -License "MIT" -Argument "--json"
        ThenTaskSucceeded
    }
}

Describe 'NodeLicenseChecker.when license reports a AGPL-1.0-or-later license and is included with --failOn' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "AGPL-1.0-or-later" -Argument $whsFailOn -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'license-checker returned a non-zero exit code.'
    }
}

Describe 'NodeLicenseChecker.when license reports a GPL-1.0-or-later license and is included with --failOn' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "GPL-1.0-or-later" -Argument $whsFailOn -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'license-checker returned a non-zero exit code.'
    }
}

Describe 'NodeLicenseChecker.when license reports a LGPL-2.0-or-later license and is included with --failOn' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "LGPL-2.0-or-later" -Argument $whsFailOn -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'license-checker returned a non-zero exit code.'
    }
}

Describe 'NodeLicenseChecker.when passing in multiple arguments.' {
    AfterEach { Reset }
    $argument = @("--json", "--failOn", "MIT", "--direct", "--production")
    It 'should pass' {
        Init
        WhenRunningTask -License "LGPL-2.0-or-later" -Argument $argument -ErrorAction SilentlyContinue
        ThenTaskSucceeded
    }
}