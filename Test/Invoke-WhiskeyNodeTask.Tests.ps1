
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$originalNodeEnv = $env:NODE_ENV
$startedWithNodeEnv = (Test-Path -Path 'env:NODE_ENV')

$defaultPackageName = 'fubarsnafu'
$context = $null
$npmRegistryUri = $null
$devDependency = @()
$dependency = @()
$ByDeveloper = $false
$WithNoName = $false
$withCleanSwitch = $false
$withInitializeSwitch = $false
$inSubDirectory = $null
$inWorkingDirectory = $null
$UsingNodeVersion = '^4.4.7'
$npmEngine = $null
$runScripts = @()
$failed = $null

function GivenNpmRegistryUri 
{
    param (
        [string]
        $registry
    )
    $Script:npmRegistryUri = $registry
}

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
function GivenSubDirectory 
{
    param (
        [string]
        $subDirectory
    )
    $script:inSubDirectory = $subDirectory
}

function GivenWorkingDirectory 
{
    param (
        [string]
        $inWorkingDirectory
    )
    $script:InWorkingDirectory = $inWorkingDirectory
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

function GivenNpmVersion
{
    param(
        $Version
    )

    $script:npmEngine = @"
        "npm": "$($Version)",
"@
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
    
    if( $script:InWorkingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $script:InWorkingDirectory
        $script:InWorkingDirectory = Join-Path -Path $script:context.BuildRoot -ChildPath $script:InWorkingDirectory
    }
    else
    {
        $script:InWorkingDirectory = $script:context.BuildRoot
    }
    if ( $script:withCleanSwitch )
    {
        $context.RunMode = 'Clean'
    }
    if ( $script:withInitializeSwitch )
    {
        $context.RunMode = 'initialize'
    }
    if ( $script:npmRegistryUri )
    {
        $taskParameter['npmRegistryUri'] = $script:npmRegistryUri
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
            (Join-Path -Path $script:InWorkingDirectory -ChildPath 'node_modules') | Should Not Exist
        }
        foreach( $taskName in $script:runScripts )
        {
            It ('should NOT run the {0} task' -f $taskName) {
                (Join-Path -Path $script:InWorkingDirectory -ChildPath $taskName) | Should Not Exist
            }
        }
        return
    }
    if( $script:withInitializeSwitch )
    {
        foreach( $taskName in $script:runScripts )
        {
            It ('should NOT run the {0} task' -f $taskName) {
                (Join-Path -Path $script:InWorkingDirectory -ChildPath $taskName) | Should Not Exist
            }
        }
        return
    }

    $versionRoot = Join-Path -Path $env:APPDATA -ChildPath ('nvm\v{0}' -f $ForVersion)
    It ('should prepend path to Node version to path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -like ('{0};*' -f $versionRoot)
        }
    }

    It ('should remove Node version path from path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -notlike ('*{0}*' -f $versionRoot)
        }
    }

    $licensePath = Join-Path -Path $script:context.OutputDirectory -ChildPath ('node-license-checker-report.json' -f $defaultPackageName)

    Context 'the licenses report' {
        It 'should exist' {
            $licensePath | Should Exist
        }

        $json = Get-Content -Raw -Path $licensePath | ConvertFrom-Json
        It 'should be parsable JSON' {
            $json | Should Not BeNullOrEmpty
        }

        It 'should be transformed from license-checker''s format' {
            $json | Select-Object -ExpandProperty 'name' | Should Not BeNullOrEmpty
            $json | Select-Object -ExpandProperty 'licenses' | Should Not BeNullOrEmpty
        }
    }

    $devDependencyPaths = Join-Path -Path $script:InWorkingDirectory -ChildPath 'package.json' | 
                            ForEach-Object { Get-Content -Raw -Path $_ } | 
                            ConvertFrom-Json |
                            Select-Object -ExpandProperty 'devDependencies' |
                            Get-Member -MemberType NoteProperty |
                            Select-Object -ExpandProperty 'Name' |
                            ForEach-Object { Join-Path -Path $script:InWorkingDirectory -ChildPath ('node_modules\{0}' -f $_)  }

    
    It 'should not prune dev dependencies' {
        $devDependencyPaths | Should Exist
    }
}

function Initialize-NodeProject
{
    if( $script:ByDeveloper )
    {
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $true } -ParameterFilter { $Path -eq 'env:NVM_HOME' }
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = (Join-Path -Path $env:APPDATA -ChildPath 'nvm') } } -ParameterFilter { $Path -eq 'env:NVM_HOME' }
        $mock = { return $false }
        Set-Item -Path 'env:NODE_ENV' -Value 'developer'
    }
    else
    {
        $mock = { return $true }
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $false } -ParameterFilter { $Path -eq 'env:HOME' }
        Set-Item -Path 'env:NODE_ENV' -Value 'production'
    }

    $version = [SemVersion.SemanticVersion]'5.4.3-rc.5+build'

    $empty = Join-Path -Path $env:Temp -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -Path $empty -ItemType 'Directory' | Out-Null
    $buildRoot = Join-Path -Path $env:Temp -ChildPath 'z'
    $workingDir = $buildRoot
    if( $script:inSubDirectory )
    {
        $workingDir = Join-Path -Path $buildRoot -ChildPath $script:inSubDirectory
    }

    try
    {
        while( (Test-Path -Path $buildRoot -PathType Container) )
        {
            Write-Verbose -Message 'Removing working directory...'
            Start-Sleep -Milliseconds 100
            robocopy $empty $buildRoot /MIR | Write-Verbose
            Remove-Item -Path $buildRoot -Recurse -Force
        }
    }
    finally
    {
        Remove-Item -Path $empty -Recurse
    }
    New-Item -Path $buildRoot -ItemType 'Directory' | Out-Null
    New-Item -Path $workingDir -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null

    Mock -CommandName 'Set-Item' -ModuleName 'Whiskey' -Verifiable

    if( -not $script:DevDependency )
    {
        $script:DevDependency = @(
                            '"rimraf": "^2.6.2"'
                          )
    }

    $nodeEngine = @"
        "node": "$($script:UsingNodeVersion)"
"@
    $packageJsonPath = Join-Path -Path $workingDir -ChildPath 'package.json'
    $name = '"name": "{0}",' -f $defaultPackageName
    if( $script:WithNoName )
    {
        $name = ''
    }
    @"
{
    $($name)
    "engines": {
        $($script:npmEngine)
        $($nodeEngine)
    },
    "private": true,
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

    Get-Content -Path $packageJsonPath -Raw | Write-Verbose -Verbose
    @'
console.log('BUILDING')
'@ | Set-Content -Path (Join-Path -Path $workingDir -ChildPath 'build.js')

    @'
console.log('TESTING')
'@ | Set-Content -Path (Join-Path -Path $workingDir -ChildPath 'test.js')

    @'
throw ('FAILING')
'@ | Set-Content -Path (Join-Path -Path $workingDir -ChildPath 'fail.js')

    $byWhoArg = @{  }
    if( $script:ByDeveloper )
    {
        $byWhoArg['ForDeveloper'] = $true
    }
    else
    {
        $byWhoArg['ForBuildServer'] = $true
    }
    $script:context = New-WhiskeyTestContext -ForBuildRoot $buildRoot -ForTaskName 'Node' -ForVersion $version @byWhoArg
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
        $Global:Error | Where-Object { $_ -match $expectedError } | Should -not -BeNullOrEmpty
    }
}

function ThenLocalNpmInstalled
{
    It 'should install a local version of npm' {
        (Join-Path -Path $script:InWorkingDirectory -ChildPath 'node_modules\npm') | Should -Exist
    }

    # npm module path in TestDrive is too long for Pester to cleanup with Remove-Item
    & cmd /C rmdir /S /Q (Join-Path -Path $script:InWorkingDirectory -ChildPath 'node_modules\npm')
}

function ThenNodeModulesAreInstalled {
    It ('should include the node_modules directory') {
        (Join-Path -Path $script:InWorkingDirectory -ChildPath 'node_modules') | Should Exist
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
    $script:inWorkingDirectory = $null
    $script:UsingNodeVersion = '^4.4.7'
    $script:npmEngine = $null
    $script:withCleanSwitch = $false
    $script:runScripts = @()
    $script:failed = $null
    $script:withInitializeSwitch = $false
}

Describe 'Node.when running a build' {
    Context 'by developer' {
        Init
        GivenBuildByDeveloper
        GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
        GivenNpmScriptsToRun 'build','test'
        Initialize-NodeProject 
        WhenBuildIsStarted
        ThenBuildSucceeds
    }
    Context 'by build server' {
        Init
        GivenBuildByBuildServer
        GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
        GivenNpmScriptsToRun 'build','test'
        Initialize-NodeProject 
        WhenBuildIsStarted
        ThenBuildSucceeds
    }
}

Describe 'Node.when a build task fails' {
    Init
    GivenBuildByDeveloper
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    GivenNpmScriptsToRun 'fail'
    Initialize-NodeProject 
    WhenBuildIsStarted -ErrorAction SilentlyContinue
    ThenBuildFails -expectedError 'npm\ run\b.*\bfailed' -NpmScript 'fail'
}

Describe 'Node.when `npm install` fails' {
    Init
    GivenBuildByDeveloper
    GivenDevDependency -DevDependency '"idonotexist": "^1.0.0"'
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    Initialize-NodeProject 
    WhenBuildIsStarted -ErrorAction SilentlyContinue
    ThenBuildFails -expectedError 'npm\ install\b.*failed'
}

Describe 'Node.when module has security vulnerability' {
    Init
    GivenBuildByDeveloper
    GivenDependency -Dependency @( '"minimatch": "3.0.0"' )
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    GivenNpmScriptsToRun 'build','test'
    Initialize-NodeProject 
    WhenBuildIsStarted
    ThenBuildFails -expectedError 'found the following security vulnerabilities' -WhoseScriptsPass
}

Describe 'Node.when user forgets to add any NpmScript' {
    Init
    GivenBuildByDeveloper
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    Initialize-NodeProject 
    WhenBuildIsStarted -WarningVariable 'warnings'

    It 'should warn that there were no NPM scripts' {
        $warnings -join [Environment]::NewLine | Should -Match 'Property ''NpmScript'' is missing or empty'
    }
}

Describe 'Node.when app is not in the root of the repository' {
    Init
    GivenSubDirectory -inWorkingDirectory 's'
    GivenBuildByDeveloper
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    GivenNpmScriptsToRun 'build','test'
    Initialize-NodeProject 
    WhenBuildIsStarted
    ThenBuildSucceeds
}

Describe 'Node.when working directory does not exist' {
    Init
    GivenBuildByDeveloper
    GivenWorkingDirectory -InWorkingDirectory 'idonotexist'
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    GivenNpmScriptsToRun 'build','test'
    Initialize-NodeProject 
    WhenBuildIsStarted -ErrorAction SilentlyContinue
    ThenBuildFails -expectedError 'WorkingDirectory\[0\] .* does not exist'
}

function GivenInstalledNodeModules
{
    New-Item -it file -Path (Join-Path -Path $context.BuildRoot -ChildPath 'node_modules\module\bin\something.js') -Force
}

Describe 'Node.when run by build server with Clean Switch' {
    Init
    GivenBuildByBuildServer
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
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

Describe 'Node.when no npm registry is provided' {
    Init
    GivenBuildByBuildServer
    GivenNpmScriptsToRun 'build','test'
    Initialize-NodeProject 
    WhenBuildIsStarted -ErrorAction SilentlyContinue
    ThenBuildFails -expectedError 'property ''NpmRegistryUri'' is mandatory'
}

Describe 'Node.when run in initialization mode' {
    Init
    GivenBuildByBuildServer
    GivenNpmRegistryUri -registry 'http://registry.npmjs.org/'
    GivenWithInitializeSwitch
    # Run a failing build to test that we just install and don't run a full build
    GivenNpmScriptsToRun 'fail'
    Initialize-NodeProject 
    WhenBuildIsStarted
    ThenNodeModulesAreInstalled
    ThenBuildSucceeds
}

if( $startedWithNodeEnv )
{
    $env:NODE_ENV = $originalNodeEnv
}
elseif( (Test-Path -Path 'env:NODE_ENV') )
{
    Remove-Item -Path 'env:NODE_ENV'
}
