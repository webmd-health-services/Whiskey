
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$shouldInitialize = $false
$failed = $false
$givenWorkingDirectory = $null
$nodeVersion = '^4.4.7'
$npmRegistryUri = 'http://registry.npmjs.org'
$npmScript = $null
$output = $null
$shouldClean = $false
$workingDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:failed = $false
    $script:givenWorkingDirectory = $null
    $script:shouldInitialize = $false
    $script:npmScript = $null
    $script:output = $null
    $script:shouldClean = $false
    $script:workingDirectory = $TestDrive.FullName
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
    "scripts": {
        "build": "node build",
        "test": "node test",
        "fail": "node fail"
    },
    "license": "MIT",
    "engines": {
        "node": "$nodeVersion"
    }
}
"@ | Set-Content -Path $packageJsonPath -Force

    @'
console.log('BUILDING')
'@ | Set-Content -Path (Join-Path -Path $script:workingDirectory -ChildPath 'build.js')

    @'
console.log('TESTING')
'@ | Set-Content -Path (Join-Path -Path $script:workingDirectory -ChildPath 'test.js')

    @'
throw ('FAILING')
'@ | Set-Content -Path (Join-Path -Path $script:workingDirectory -ChildPath 'fail.js')

}

function GivenFailingNpmInstall
{
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $NpmCommand -eq 'install' } -MockWith { & cmd /c exit 1 }
}

function GivenInitializeMode
{
    $script:shouldInitialize = $true
    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -MockWith { & cmd /c exit 0 }
}

function GivenCleanMode
{
    $script:shouldClean = $true
    Mock -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey' 
}

function GivenScript
{
    param(
        [string[]]
        $Script
    )
    $script:npmScript = $Script
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

    if ($npmScript)
    {
        $taskParameter['Script'] = $npmScript
    }

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

    try
    {
        CreatePackageJson

        $script:output = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmRunScript'
        $script:output = $script:output -join [Environment]::NewLine
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenNpmInitialized
{
    It 'should initialize Node and NPM' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $InitializeOnly -eq $true } -Times 1
    }
}

function ThenNpmRunNotCalled
{
    It 'should not call ''npm run''' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $NpmCommand -eq 'run' } -Times 0
    }
}

function ThenScript
{
    param(
        [Parameter(Position=0)]
        [string]
        $ScriptName,

        [Parameter(Mandatory=$true,ParameterSetName='Ran')]
        [switch]
        $Ran,

        [Parameter(Mandatory=$true,ParameterSetName='DidNotRun')]
        [switch]
        $DidNotRun
    )

    $expectedScriptOutput = @{
        'build' = 'BUILDING'
        'test'  = 'TESTING'
    }

    If ($Ran)
    {
        It ('should run script ''{0}''' -f $ScriptName) {
            $script:output | Should -Match $expectedScriptOutput[$ScriptName]
        }

    }
    else
    {
        It ('should not run script ''{0}''' -f $ScriptName) {
            $script:output | Should -Not -Match $expectedScriptOutput[$ScriptName]
        }
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

function ThenNodeModulesCleaned
{
    It 'should remove the ''node_modules'' directory' {
        $nodeModulesDir = Join-Path -Path $workingDirectory -ChildPath 'node_modules'

        $nodeModulesDir | Should -Not -Exist
    }
}

function ThenTaskSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
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

Describe 'NpmRunScript.when running in Clean mode' {
    Init
    GivenScript 'build','test'
    GivenCleanMode
    WhenRunningTask
    ThenUninstalledModule 'npm'
    ThenScript 'build' -DidNotRun
    ThenScript 'test' -DidNotRun
    ThenTaskSucceeded
}

Describe 'NpmRunScript.when running in Initialize mode' {
    Init
    GivenScript 'build','test'
    GivenInitializeMode
    WhenRunningTask
    ThenNpmInitialized
    ThenNpmRunNotCalled
    ThenTaskSucceeded
}

Describe 'NpmRunScript.when not given any Scripts to run' {
    Init
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenScript 'build' -DidNotRun
    ThenScript 'test' -DidNotRun
    ThenTaskFailedWithMessage 'Property ''Script'' is mandatory.'
}

Describe 'NpmRunScript.when running scripts' {
    Init
    GivenScript 'build','test'
    WhenRunningTask
    ThenScript 'build' -Ran
    ThenScript 'test' -Ran
    ThenTaskSucceeded
}

Describe 'NpmRunScript.when given working directory' {
    Init
    GivenScript 'build'
    GivenWorkingDirectory 'src\app'
    WhenRunningTask
    ThenScript 'build' -Ran
    ThenTaskSucceeded
}

Describe 'NpmRunScript.when running failing script' {
    Init
    GivenScript 'fail'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'NPM script ''fail'' failed'
}
