
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
$npmScript = $null
$output = $null

function Init
{
    $Global:Error.Clear()
    $script:failed = $false
    $script:shouldInitialize = $false
    $script:npmScript = $null
    $script:output = $null
    $script:shouldClean = $false
    Install-Node
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
    "scripts": {
        "build": "node build",
        "test": "node test",
        "fail": "node fail"
    },
    "license": "MIT"
}
"@ | Set-Content -Path $packageJsonPath -Force

    @'
console.log('BUILDING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'build.js')

    @'
console.log('TESTING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'test.js')

    @'
throw ('FAILING')
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'fail.js')

}

function GivenScript
{
    param(
        [string[]]
        $Script
    )
    $script:npmScript = $Script
}

function WhenRunningTask
{
    [CmdletBinding()]
    param()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    if ($npmScript)
    {
        $taskParameter['Script'] = $npmScript
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
        $Global:Error | Where-Object { $_ -match $Message } | Should -Not -BeNullOrEmpty
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

Describe 'NpmRunScript.when not given any Scripts to run' {
    try
    {
        Init
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenScript 'build' -DidNotRun
        ThenScript 'test' -DidNotRun
        ThenTaskFailedWithMessage 'Property ''Script'' is mandatory.'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmRunScript.when running scripts' {
    Init
    try
    {
        GivenScript 'build','test'
        WhenRunningTask
        ThenScript 'build' -Ran
        ThenScript 'test' -Ran
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmRunScript.when running failing script' {
    try
    {
        Init
        GivenScript 'fail'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'failed\ with\ exit\ code\ 1'
    }
    finally
    {
        Remove-Node
    }
}
