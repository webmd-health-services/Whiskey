
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$dependency = $null
$devDependency = $null
$failed = $false
$licenseReportPath = $null
$output = $null

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:output = $null

    $script:testRoot = New-WhiskeyTestRoot

    $script:licenseReportPath = Join-Path -Path $testRoot -ChildPath '.output\node-license-checker-report.json'
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

function GivenBadJson
{
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'ConvertFrom-Json' }
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

function ThenLicenseReportCreated
{
    $licenseReportPath | Should -Exist
}

function ThenLicenseReportIsValidJSON
{
    $licenseReportJson = Get-Content -Path $licenseReportPath -Raw | ConvertFrom-Json

    $licenseReportJson | Should -Not -BeNullOrEmpty
}

function ThenLicenseReportNotCreated
{
    $licenseReportPath | Should -Not -Exist
}

function ThenLicenseReportFormatTransformed
{
    $licenseReportJson = Get-Content -Path $licenseReportPath -Raw | ConvertFrom-Json

    $licenseReportJson | Select-Object -ExpandProperty 'name' | Should -Not -BeNullOrEmpty
    $licenseReportJson | Select-Object -ExpandProperty 'licenses' | Should -Not -BeNullOrEmpty
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
        [String]$License
    )

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $testRoot

    $taskParameter = @{ }

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
        WhenRunningTask -License "MIT"
        ThenLicenseReportCreated
        ThenLicenseReportIsValidJSON
        ThenLicenseReportFormatTransformed
        ThenTaskSucceeded
    }
}

Describe 'NodeLicenseChecker.when license checker did not return valid JSON' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenBadJson
        WhenRunningTask -License "MIT" -ErrorAction SilentlyContinue
        ThenLicenseReportNotCreated
        ThenTaskFailedWithMessage 'failed to output a valid JSON report'
    }
}

Describe 'NodeLicenseChecker.when license reports a AGPL-1.0-or-later license' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "AGPL-1.0-or-later" -ErrorAction SilentlyContinue
        ThenLicenseReportNotCreated
        ThenTaskFailedWithMessage 'license-checker reported a prohibited'
    }
}

Describe 'NodeLicenseChecker.when license reports a GPL-1.0-or-later license' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "GPL-1.0-or-later" -ErrorAction SilentlyContinue
        ThenLicenseReportNotCreated
        ThenTaskFailedWithMessage 'license-checker reported a prohibited'
    }
}

Describe 'NodeLicenseChecker.when license reports a LGPL-2.0-or-later license' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenRunningTask -License "LGPL-2.0-or-later" -ErrorAction SilentlyContinue
        ThenLicenseReportNotCreated
        ThenTaskFailedWithMessage 'license-checker reported a prohibited'
    }
}