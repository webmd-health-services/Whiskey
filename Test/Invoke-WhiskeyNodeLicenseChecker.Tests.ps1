
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$npmRegistryUri = 'http://registry.npmjs.org'
$licenseReportPath = $null
$output = $null

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:output = $null
    $script:licenseReportPath = Join-Path -Path $TestDrive.FullName -ChildPath '.output\node-license-checker-report.json'
    Install-Node -WithModule 'license-checker'
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
}

function GivenBadJson
{
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'ConvertFrom-Json' }
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

function WhenRunningTask
{
    [CmdletBinding()]
    param()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    try
    {
        CreatePackageJson

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NodeLicenseChecker'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenLicenseCheckerNotRun
{
    It 'should not run license-checker' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match '--json' } -Times 0
    }
}

function ThenLicenseReportCreated
{
    It 'should create the license report' {
        $licenseReportPath | Should -Exist
    }
}

function ThenLicenseReportIsValidJSON
{
    $licenseReportJson = Get-Content -Path $licenseReportPath -Raw | ConvertFrom-Json

    It 'should be valid JSON' {
        $licenseReportJson | Should -Not -BeNullOrEmpty
    }
}

function ThenLicenseReportNotCreated
{
    It 'should not create the license report' {
        $licenseReportPath | Should -Not -Exist
    }
}

function ThenLicenseReportFormatTransformed
{
    $licenseReportJson = Get-Content -Path $licenseReportPath -Raw | ConvertFrom-Json

    It 'should transform the license report format to a more readable structure' {
        $licenseReportJson | Select-Object -ExpandProperty 'name' | Should -Not -BeNullOrEmpty
        $licenseReportJson | Select-Object -ExpandProperty 'licenses' | Should -Not -BeNullOrEmpty
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
    # filter out the NPM Warn messages out of the error record
    $TaskErrors = $Global:Error | Where-Object { $_ -notmatch 'npm WARN' }
    It 'should not write any errors' {
        $TaskErrors | Should -BeNullOrEmpty
    }

    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NodeLicenseChecker.when running license-checker' {
    try
    {
        Init
        WhenRunningTask
        ThenLicenseReportCreated
        ThenLicenseReportIsValidJSON
        ThenLicenseReportFormatTransformed
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NodeLicenseChecker.when license checker did not return valid JSON' {
    try
    {
        Init
        GivenBadJson
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenLicenseReportNotCreated
        ThenTaskFailedWithMessage 'failed to output a valid JSON report'
    }
    finally
    {
        Remove-Node
    }
}
