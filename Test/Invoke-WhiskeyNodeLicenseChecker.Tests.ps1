
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$givenWorkingDirectory = $null
$npmRegistryUri = 'http://registry.npmjs.org'
$nodeVersion = '^4.4.7'
$licenseReportPath = $null
$output = $null
$shouldClean = $false
$shouldInitialize = $false
$workingDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:givenWorkingDirectory = $null
    $script:output = $null
    $script:shouldClean = $false
    $script:shouldInitialize = $false
    $script:workingDirectory = $TestDrive.FullName
    $script:licenseReportPath = Join-Path -Path $TestDrive.FullName -ChildPath '.output\node-license-checker-report.json'
}

function CreatePackageJson
{
    $packageJsonPath = Join-Path -Path $script:workingDirectory -ChildPath 'package.json'

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

function GivenCleanMode
{
    $script:shouldClean = $true
    Mock -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey'
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match '--json' }
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

function GivenInitializeMode
{
    $script:shouldInitialize = $true
    Mock -CommandName 'Install-WhiskeyNodeModule' -ModuleName 'Whiskey' -MockWith { $TestDrive.FullName }
    Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -ParameterFilter { $ChildPath -eq 'bin\license-checker' } -MockWith { $TestDrive.FullName }
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match '--json' }
}

function GivenWorkingDirectory
{
    param(
        $Directory
    )
    $script:givenWorkingDirectory = $Directory
    $script:workingDirectory = Join-Path -Path $workingDirectory -ChildPath $Directory

    New-Item -Path $workingDirectory -ItemType 'Directory' -Force | Out-Null
}

function WhenRunningTask
{
    [CmdletBinding()]
    param()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName
    
    $taskParameter = @{ 'NpmRegistryUri' = $script:npmRegistryUri }

    if ($givenWorkingDirectory)
    {
        $taskParameter['WorkingDirectory'] = $givenWorkingDirectory
    }

    if ($shouldClean)
    {
        $taskContext.RunMode = 'Clean'
    }
    elseif ($shouldInitialize)
    {
        $taskContext.RunMode = 'Initialize'
    }

    Push-Location $script:workingDirectory

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
    finally
    {
        Pop-Location
    }
}

function ThenLicenseCheckerInstalled
{
    It 'should install the license-checker module' {
        Assert-MockCalled -CommandName 'Install-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'license-checker' } -Times 1        
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

function ThenUninstalledModule
{
    param(
        $ModuleName
    )

    It ('should uninstall the ''{0}'' module' -f $ModuleName) {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModuleName } -Times 1
    }
}

Describe 'NodeLicenseChecker.when running in Clean mode' {
    Init
    GivenCleanMode
    WhenRunningTask
    ThenUninstalledModule 'npm'
    ThenUninstalledModule 'license-checker'
    ThenLicenseCheckerNotRun
    ThenTaskSucceeded
}

Describe 'NodeLicenseChecker.when running in Initialize mode' {
    Init
    GivenInitializeMode
    WhenRunningTask
    ThenLicenseCheckerInstalled
    ThenLicenseCheckerNotRun
    ThenTaskSucceeded
}

Describe 'NodeLicenseChecker.when running license-checker' {
    Init
    WhenRunningTask
    ThenLicenseReportCreated
    ThenLicenseReportIsValidJSON
    ThenLicenseReportFormatTransformed
    ThenTaskSucceeded
}

Describe 'NodeLicenseChecker.when given working directory' {
    Init
    GivenWorkingDirectory 'src\app'
    WhenRunningTask
    ThenLicenseReportCreated
    ThenLicenseReportIsValidJSON
    ThenLicenseReportFormatTransformed
    ThenTaskSucceeded
}

Describe 'NodeLicenseChecker.when license checker did not return valid JSON' {
    Init
    GivenBadJson
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenLicenseReportNotCreated
    ThenTaskFailedWithMessage 'failed to output a valid JSON report'
}
