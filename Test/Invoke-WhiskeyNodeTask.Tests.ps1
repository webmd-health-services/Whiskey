
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$originalNodeEnv = $env:NODE_ENV
$startedWithNodeEnv = (Test-Path -Path 'env:NODE_ENV')

$defaultPackageName = 'fubarsnafu'
$context = $null
$devDependency = @()
$dependency = @()
$ByDeveloper = $false
$WithNoName = $false
$withCleanSwitch = $false
$withInitializeSwitch = $false
$inSubDirectory = $null
$runScripts = @()
$failed = $null

function GivenEnvironment 
{
    param (
        [string]
        $env
    )
    $env:NODE_ENV = $env
}
function GivenNpmScriptsToRun 
{
    param (
        [string[]]
        $scripts
    )
    $script:runScripts = $scripts
}

function GivenWithCleanSwitch 
{
    $script:withCleanSwitch = $true
}

function GivenWithInitializeSwitch
{
    $script:withInitializeSwitch = $true
}

function GivenBuildByDeveloper 
{
    $script:ByDeveloper = $true
}

function GivenBuildByBuildServer 
{
    $script:ByDeveloper = $false
}

function GivenDevDependency 
{
    param(
        [object[]]
        $DevDependency 
    )
    $script:devDependency = $DevDependency
}

function GivenDependency 
{
    param(
        [object[]]
        $Dependency 
    )
    $script:dependency = $Dependency
}

function GivenNoName 
{
    $script:WithNoName = $true
}

function WhenBuildIsStarted
{
    [CmdletBinding()]
    param(
        [string]
        $ForVersion = '4.4.7'
    )
    $Global:Error.Clear()
    $optionalParams = @{ }

    $taskParameter = @{ }

    if( $script:runScripts )
    {
        $taskParameter['NpmScript'] = $script:runScripts
    }
    
    if ( $script:withCleanSwitch )
    {
        $context.RunMode = 'Clean'
    }
    if ( $script:withInitializeSwitch )
    {
        $context.RunMode = 'initialize'
    }
    $Global:Error.Clear()
    $script:failed = $false
    try
    {
        Invoke-WhiskeyTask -TaskContext $script:context -Parameter $taskParameter -Name 'Node'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
        return
    }
    if( $script:withCleanSwitch )
    {
        It ('should remove the node_modules directory') {
            (Join-Path -Path $TestDrive.FullName -ChildPath 'node_modules') | Should Not Exist
        }
        foreach( $taskName in $script:runScripts )
        {
            It ('should NOT run the {0} task' -f $taskName) {
                (Join-Path -Path $TestDrive.FullName -ChildPath $taskName) | Should Not Exist
            }
        }
        return
    }
    if( $script:withInitializeSwitch )
    {
        foreach( $taskName in $script:runScripts )
        {
            It ('should NOT run the {0} task' -f $taskName) {
                (Join-Path -Path $TestDrive.FullName -ChildPath $taskName) | Should Not Exist
            }
        }
        return
    }

    It ('should prepend path to Node version to path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -like ('{0}\.node;*' -f $TestDrive.FullName)
        }
    }

    It ('should remove Node version path from path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -notlike ('*{0}\.node*' -f $TestDrive.FullName)
        }
    }

    $licensePath = Join-Path -Path $script:context.OutputDirectory -ChildPath ('node-license-checker-report.json' -f $defaultPackageName)

    It 'the licenses report should exist' {
        $licensePath | Should Exist
    }

    $json = Get-Content -Raw -Path $licensePath | ConvertFrom-Json
    It 'the licenses report should be parsable JSON' {
        $json | Should Not BeNullOrEmpty
    }

    It 'the licenses report should be transformed from license-checker''s format' {
        $json | Select-Object -ExpandProperty 'name' | Should Not BeNullOrEmpty
        $json | Select-Object -ExpandProperty 'licenses' | Should Not BeNullOrEmpty
    }

    $devDependencyPaths = Join-Path -Path $TestDrive.FullName -ChildPath 'package.json' | 
                            ForEach-Object { Get-Content -Raw -Path $_ } | 
                            ConvertFrom-Json |
                            Select-Object -ExpandProperty 'devDependencies' |
                            Get-Member -MemberType NoteProperty |
                            Select-Object -ExpandProperty 'Name' |
                            ForEach-Object { Join-Path -Path $TestDrive.FullName -ChildPath ('node_modules\{0}' -f $_)  }

    It 'should not prune dev dependencies' {
        $devDependencyPaths | Should Exist
    }
}

function Initialize-NodeProject
{
    if( $script:ByDeveloper )
    {
        $mock = { return $false }
        Set-Item -Path 'env:NODE_ENV' -Value 'developer'
    }
    else
    {
        $mock = { return $true }
        Set-Item -Path 'env:NODE_ENV' -Value 'production'
    }

    $version = [SemVersion.SemanticVersion]'5.4.3-rc.5+build'

    Mock -CommandName 'Set-Item' -ModuleName 'Whiskey' -Verifiable

    if( -not $script:DevDependency )
    {
        $script:DevDependency = @(
                            '"rimraf": "^2.6.2"'
                          )
    }

    $packageJsonPath = Join-Path -Path $TestDrive.FullName -ChildPath 'package.json'
    $name = '"name": "{0}",' -f $defaultPackageName
    if( $script:WithNoName )
    {
        $name = ''
    }
    @"
{
    $($name)
    "private": true,
    "version": "0.0.1",
    "scripts": {
        "build": "node build",
        "test": "node test",
        "fail": "node fail"
    },

    "dependencies": {
        $( $script:Dependency -join ',' )
    },

    "devDependencies": {
        $( $script:DevDependency -join "," )
    }
}
"@ | Set-Content -Path $packageJsonPath

    @"
{
    $($name)
    "version": "0.0.1",
    "lockfileVersion": 1,
    "requires": true,
    "dependencies": {
    }
}
"@ | Set-Content -Path (Join-Path -Path ($packageJsonPath | Split-Path) -ChildPath 'package-lock.json')

    @'
console.log('BUILDING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'build.js')

    @'
console.log('TESTING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'test.js')

    @'
throw ('FAILING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'fail.js')

    $byWhoArg = @{  }
    if( $script:ByDeveloper )
    {
        $byWhoArg['ForDeveloper'] = $true
    }
    else
    {
        $byWhoArg['ForBuildServer'] = $true
    }
    $script:context = New-WhiskeyTestContext -ForTaskName 'Node' -ForVersion $version @byWhoArg
}

function ThenBuildSucceeds 
{
    It 'should not fail' {
        $failed | Should -Be $false
    }
}

function ThenBuildFails 
{
    param(
        [string]
        $expectedError,

        [switch]
        $whoseScriptsPass,

        [object[]]
        $NpmScript
    )
    foreach( $script in $NpmScript )
    {
        if( $WhoseScriptsPass )
        {
            It ('should run ''{0}'' NPM script' -f $script) {
                Join-Path -Path $script:context.BuildRoot -ChildPath $script | Should Exist
            }
        }
        else
        {
            It ('should not run ''{0}'' NPM script' -f $script) {
                Join-Path -Path $script:context.BuildRoot -ChildPath $script | Should Not Exist
            }
        }
    }
    It 'should throw an exception' {
        $failed | Should -Be $true
        $Global:Error | Where-Object { ($_ | Out-String) -match $expectedError } | Should -not -BeNullOrEmpty
    }
}

function ThenNodeModulesAreInstalled {
    It ('should include the node_modules directory') {
        (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node_modules\license-checker') | Should -Exist
        (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node_modules\nsp') | Should -Exist
    }
}

function ThenPackagesCleaned
{
    It ('should clean packages directory') {
        Join-Path -Path $context.BuildRoot -ChildPath 'node_modules' | Should -Not -Exist
    }
}

function Init 
{
    $script:context = $null
    $script:npmRegistryUri = $null
    $script:devDependency = @()
    $script:dependency = @()
    $script:ByDeveloper = $false
    $script:WithNoName = $false
    $script:withCleanSwitch = $false
    $script:runScripts = @()
    $script:failed = $null
    $script:withInitializeSwitch = $false
    Install-Node -WithModule 'license-checker'
}

Describe 'Node.when running a build' {
    Context 'by developer' {
        try
        {
            Init
            GivenBuildByDeveloper
            GivenNpmScriptsToRun 'build','test'
            Initialize-NodeProject 
            WhenBuildIsStarted
            ThenBuildSucceeds
        }
        finally
        {
            Remove-Node
        }
    }
    Context 'by build server' {
        try
        {
            Init
            GivenBuildByBuildServer
            GivenNpmScriptsToRun 'build','test'
            Initialize-NodeProject 
            WhenBuildIsStarted
            ThenBuildSucceeds
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'Node.when a build task fails' {
    try
    {
        Init
        GivenBuildByDeveloper
        GivenNpmScriptsToRun 'fail'
        Initialize-NodeProject 
        WhenBuildIsStarted -ErrorAction SilentlyContinue
        $errMsg = 'npm\ run\b.*\bfailed'
        if( $Host.Name -like '*ISE*' )
        {
            $errMsg = 'node\.exe\ :'
        }
        ThenBuildFails -expectedError $errMsg -NpmScript 'fail'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Node.when `npm install` fails' {
    try
    {
        Init
        GivenBuildByDeveloper
        GivenDevDependency -DevDependency '"idonotexist": "^1.0.0"'
        Initialize-NodeProject 
        WhenBuildIsStarted -ErrorAction SilentlyContinue
        $errMsg = 'npm\ run\b.*\bfailed'
        if( $Host.Name -like '*ISE*' )
        {
            $errMsg = 'node\.exe\ :'
        }
        ThenBuildFails -expectedError $errMsg
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Node.when module has security vulnerability' {
    try
    {
        Init
        GivenBuildByDeveloper
        GivenDependency -Dependency @( '"minimatch": "3.0.0"' )
        GivenNpmScriptsToRun 'build','test'
        Initialize-NodeProject 
        WhenBuildIsStarted -ErrorAction SilentlyContinue
        ThenBuildFails -expectedError 'found the following security vulnerabilities' -WhoseScriptsPass
    }
    finally
    {
        Remove-Node
    }
}

function GivenInstalledNodeModules
{
    New-Item -it file -Path (Join-Path -Path $context.BuildRoot -ChildPath 'node_modules\module\bin\something.js') -Force
}

Describe 'Node.when run by build server with Clean Switch' {
    try
    {
        Init
        GivenBuildByBuildServer
        Initialize-NodeProject
        GivenInstalledNodeModules
        GivenWithCleanSwitch
        WhenBuildIsStarted
        ThenBuildSucceeds
        ThenPackagesCleaned
        # Run again to make sure we don't get an error if there isn't a directory to clean.
        WhenBuildIsStarted
        ThenBuildSucceeds
        ThenPackagesCleaned
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Node.when run in initialization mode' {
    try
    {
        Init
        GivenBuildByBuildServer
        GivenWithInitializeSwitch
        # Run a failing build to test that we just install and don't run a full build
        GivenNpmScriptsToRun 'fail'
        Initialize-NodeProject 
        WhenBuildIsStarted
        ThenNodeModulesAreInstalled
        ThenBuildSucceeds
    }
    finally
    {
        Remove-Node
    }
}

if( $startedWithNodeEnv )
{
    $env:NODE_ENV = $originalNodeEnv
}
elseif( (Test-Path -Path 'env:NODE_ENV') )
{
    Remove-Item -Path 'env:NODE_ENV'
}
