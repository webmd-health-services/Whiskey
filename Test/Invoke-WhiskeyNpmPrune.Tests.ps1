Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$initialize = $null
$failed = $false
$nodeVersion = '^4.4.7'
$npmRegistryUri = 'http://registry.npmjs.org'
$givenWorkingDirectory = $null
$workingDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:initialize = $null
    $script:failed = $false
    $script:givenWorkingDirectory = $null
    $script:workingDirectory = $TestDrive.FullName
}

function GivenPackageJson
{
    $packageJsonPath = Join-Path -Path $script:workingDirectory -ChildPath 'package.json'

    @"
{
    "name": "NpmPrune-Test-App",
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

function Initialize-NodeProject
{
    # Run npm install so we have things to prune
    $nodePath = Install-WhiskeyNodeJs -RegistryUri $script:npmRegistryUri -ApplicationRoot $script:workingDirectory
    $npmPath = (Join-Path -Path ($NodePath | Split-Path) -ChildPath 'node_modules\npm\bin\npm-cli.js' -Resolve)
    
    Push-Location -Path $script:workingDirectory
    try
    {
        & $nodePath $npmPath install
    }
    finally
    {
        Pop-Location
    }
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
    $script:initialize = $true

    Mock -CommandName 'Initialize-NodeProject'
    Mock -CommandName 'Install-WhiskeyNodeJs' -ModuleName 'Whiskey' -ParameterFilter { $ApplicationRoot -eq $workingDirectory }
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock -match 'prune' }
}

function GivenFailingNpm
{
    param (
        $ExitCode
    )

    Mock -CommandName 'Initialize-NodeProject'
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock -match 'prune' } -MockWith { & cmd /c exit 1 }
}

function GivenMissingPackageJson
{
    Mock -CommandName 'Initialize-NodeProject'
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

    if ($initialize)
    {
        $taskContext.RunMode = 'Initialize'
    }

    try
    {
        Initialize-NodeProject

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmPrune'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenNodeJsInstalled
{
    It 'should install Node.js' {
        Assert-MockCalled -CommandName 'Install-WhiskeyNodeJs' -ModuleName 'Whiskey' -ParameterFilter { $ApplicationRoot -eq $workingDirectory } -Times 1
    }
}

function ThenNpmPruneNotCalled
{
    It 'should not run ''npm prune''' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock -match 'prune' } -Times 0
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

    $packagePath = Join-Path -Path $script:workingDirectory -ChildPath ('node_modules\{0}' -f $PackageName)

    If ($Exists)
    {
        It ('should not prune package ''{0}''' -f $PackageName) {
            $packagePath | Should -Exist
        }
    }
    else
    {
        It ('should prune package ''{0}''' -f $PackageName) {
            $packagePath | Should -Not -Exist
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

function ThenTaskSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NpmPrune.when running in Initialize mode' {
    Init
    GivenInitializeMode
    GivenPackageJson
    WhenRunningTask
    ThenNodeJsInstalled
    ThenNpmPruneNotCalled
    ThenTaskSucceeded
}
Describe 'NpmPrune.when missing package.json' {
    Init
    GivenMissingPackageJson
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage '''package.json'' file does not exist'
}

Describe 'NpmPrune.when pruning packages' {
    Init
    GivenDependency '"wrappy": "^1.0.2"'
    GivenDevDependency '"pify": "^3.0.0"'
    GivenPackageJson
    WhenRunningTask
    ThenPackage 'wrappy' -Exists
    ThenPackage 'pify' -DoesNotExist
    ThenTaskSucceeded
}

Describe 'NpmPrune.when pruning packages with given working directory' {
    Init
    GivenWorkingDirectory 'workdir'
    GivenDependency '"wrappy": "^1.0.2"'
    GivenDevDependency '"pify": "^3.0.0"'
    GivenPackageJson
    WhenRunningTask
    ThenPackage 'wrappy' -Exists
    ThenPackage 'pify' -DoesNotExist
    ThenTaskSucceeded
}

Describe 'NpmPrune.when npm returns non-zero exit code' {
    Init
    GivenDependency '"wrappy": "^1.0.2"'
    GivenDevDependency '"pify": "^3.0.0"'
    GivenFailingNpm
    GivenPackageJson
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'NPM command ''npm prune'' failed with exit code' 
}
