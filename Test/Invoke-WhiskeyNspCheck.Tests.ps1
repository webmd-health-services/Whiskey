
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$givenWorkingDirectory = $null
$npmRegistryUri = 'http://registry.npmjs.org'
$nodeVersion = '^8.9.3'
$output = $null
$shouldClean = $false
$shouldInitialize = $false
$workingDirectory = $null
$nspVersion = $null

function Init
{
    $script:dependency = $null
    $script:devDependency = $null
    $Global:Error.Clear()
    $script:failed = $false
    $script:givenWorkingDirectory = $null
    $script:output = $null
    $script:shouldClean = $false
    $script:shouldInitialize = $false
    $script:workingDirectory = $TestDrive.FullName
    $script:nspVersion = $null
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

function MockNsp
{
    param(
        [switch]
        $Failing
    )

    Mock -CommandName 'Install-WhiskeyNodeModule' -ModuleName 'Whiskey' -MockWith { $TestDrive.FullName }
    Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -ParameterFilter { $ChildPath -eq 'bin\nsp' } -MockWith { $TestDrive.FullName }
    
    if (-not $Failing)
    {
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -MockWith { & cmd /c 'ECHO [] && exit 0' }
    }
    else
    {
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -MockWith { & cmd /c 'ECHO An error has occured && exit 1' }
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

function GivenCleanMode
{
    $script:shouldClean = $true
    Mock -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey'
}

function GivenInitializeMode
{
    $script:shouldInitialize = $true
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

function GivenNspVersion
{
    param(
        $Version
    )

    $script:nspVersion = $Version
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

    if ($nspVersion)
    {
        $taskParameter['NspVersion'] = $nspVersion
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

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NspCheck'
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

function ThenNspInstalled
{
    param(
        $WithVersion
    )

    It 'should install NSP module' {
        Assert-MockCalled -CommandName 'Install-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'nsp' } -Times 1        
    }

    if( $WithVersion )
    {
        It ('should install NSP version ''{0}''' -f $WithVersion) {
            Assert-MockCalled -CommandName 'Install-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Version -eq $WithVersion } -Times 1
        }
    }
}

function ThenNspNotRun
{
    It 'should not run ''nsp check''' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -Times 0
    }
}

function ThenNspRan
{
    param(
        $WithVersion
    )

    It 'should run ''nsp check''' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -Times 1
    }

    if( $WithVersion )
    {
        if( $WithVersion -gt (ConvertTo-WhiskeySemanticVersion -InputObject '2.7.0') )
        {
            It 'should run ''nsp check'' with ''--reporter'' json formatting argument' {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $argumentList -eq '--reporter' } -Times 1
            }
        }
        else
        {
            It 'should run ''nsp check'' with ''--output'' json formatting argument' {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $argumentList -eq '--output' } -Times 1
            }
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
    for( $i = $Global:Error.Count - 1; $i -ge 0; $i-- )
    {
        if( $Global:Error[$i] -match 'npm notice created a lockfile as package-lock.json. You should commit this file.' )
        {
            $Global:Error.RemoveAt($i)
        }
    }
    
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

Describe 'NspCheck.when running in Clean mode' {
    Init
    MockNsp
    GivenCleanMode
    WhenRunningTask
    ThenUninstalledModule 'npm'
    ThenUninstalledModule 'nsp'
    ThenNspNotRun
    ThenTaskSucceeded
}

Describe 'NspCheck.when running in Initialize mode' {
    Init
    MockNsp
    GivenInitializeMode
    WhenRunningTask
    ThenNspInstalled
    ThenNspNotRun
    ThenTaskSucceeded
}

Describe 'NspCheck.when running nsp check' {
    Init
    MockNsp
    WhenRunningTask
    ThenNspInstalled
    ThenNspRan
    ThenTaskSucceeded
}

Describe 'NspCheck.when running nsp in given working directory' {
    Init
    GivenWorkingDirectory 'src\app'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskSucceeded
}

Describe 'NspCheck.when module has a security vulnerability' {
    Init
    GivenDependency '"minimatch": "3.0.0"'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'found the following security vulnerabilities'
}

Describe 'NspCheck.when nsp does not return valid JSON' {
    Init
    MockNsp -Failing
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'did not return valid JSON'
}

Describe 'NspCheck.when running nsp check specifically with v2.7.0' {
    Init
    GivenNspVersion '2.7.0'
    MockNsp
    WhenRunningTask
    ThenNspInstalled -WithVersion '2.7.0'
    ThenNspRan -WithVersion '2.7.0'
    ThenTaskSucceeded
}

Describe 'NspCheck.when running nsp check specifically with v3.1.0' {
    Init
    GivenNspVersion '3.1.0'
    MockNsp
    WhenRunningTask
    ThenNspInstalled -WithVersion '3.1.0'
    ThenNspRan -WithVersion '3.1.0'
    ThenTaskSucceeded
}
