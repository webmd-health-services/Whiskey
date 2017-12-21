
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$shouldInitialize = $false
$failed = $false
$givenWorkingDirectory = $null
$nodeVersion = '^4.4.7'
$npmRegistryUri = 'http://registry.npmjs.org'
$package = @()
$shouldClean = $false
$workingDirectory = $null

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:givenWorkingDirectory = $null
    $script:shouldInitialize = $false
    $script:package = @()
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
    Mock -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'npm' }
}

function GivenNodeModulesDirectoryExists
{
    New-Item -Path (Join-Path -Path $workingDirectory -ChildPath 'node_modules') -ItemType Directory -Force | Out-Null
}

function GivenPackage
{
    param(
        $Package
    )
    $script:package += $Package
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

    if ($package)
    {
        $taskParameter['Package'] = $package
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

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmInstall'
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

function ThenNpmInstallNotCalled
{
    It 'should not run ''npm install''' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $NpmCommand -eq 'install' } -Times 0
    }
}

function ThenPackage
{
    param(
        [Parameter(Position=0)]
        [string]
        $PackageName,

        [Parameter(Mandatory=$false,ParameterSetName='Exists')]
        [string]
        $Version,
        
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
        It ('should install package ''{0}''' -f $PackageName) {
            $packagePath | Should -Exist
        }

        if ($Version)
        {
            $packageVersion = Get-Content -Path (Join-Path -Path $packagePath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'Version'
            It ('''{0}'' should be version ''{1}''' -f $PackageName,$Version) {
                $packageVersion | Should -Be $Version
            }
        }
    }
    else
    {
        It ('should remove package ''{0}''' -f $PackageName) {
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

function ThenUninstalledModule
{
    param(
        $ModuleName
    )

    It ('should uninstall the ''{0}'' module' -f $ModuleName) {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModuleName } -Times 1
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

Describe 'NpmInstall.when running in Clean mode' {
    Init
    GivenCleanMode
    WhenRunningTask
    ThenUninstalledModule 'npm'
    ThenTaskSucceeded
}

Describe 'NpmInstall.when running in Initialize mode' {
    Init
    GivenInitializeMode
    WhenRunningTask
    ThenNpmInitialized
    ThenNpmInstallNotCalled
    ThenTaskSucceeded
}

Describe 'NpmInstall.when ''npm install'' fails' {
    Init
    GivenFailingNpmInstall
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'Failed to install Node dependencies listed in'
}

Describe 'NpmInstall.when installing packages from package.json' {
    Init
    GivenDependency '"wrappy": "^1.0.2"'
    GivenDevDependency '"pify": "^3.0.0"'
    WhenRunningTask
    ThenPackage 'wrappy' -Exists
    ThenPackage 'pify' -Exists
    ThenTaskSucceeded
}

Describe 'NpmInstall.when given package' {
    Init
    GivenPackage 'rimraf'
    GivenPackage 'pify'
    GivenDependency '"wrappy": "^1.0.2"'
    WhenRunningTask
    ThenPackage 'rimraf' -Exists
    ThenPackage 'pify' -Exists
    ThenPackage 'wrappy' -DoesNotExist
    ThenTaskSucceeded
}

Describe 'NpmInstall.when given package with version number' {
    Init
    GivenPackage 'pify'
    GivenPackage @{ 'wrappy' = '1.0.2' }
    WhenRunningTask
    ThenPackage 'pify' -Exists
    ThenPackage 'wrappy' -Version '1.0.2' -Exists
    ThenTaskSucceeded
}


Describe 'NpmInstall.when given working directory' {
    Init
    GivenWorkingDirectory 'src\app'
    GivenDependency '"wrappy": "^1.0.2"'
    WhenRunningTask
    ThenPackage 'wrappy' -Exists
    ThenTaskSucceeded
}
