
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$failed = $false

function GivenFile
{
    param(
        $Path,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $testRoot -ChildPath $Path)
}

function Init
{
    $script:failed = $false
    # Tasks get loaded into Whiskey's scope, so we have to unload it to clear any previosly loaded tasks.
    Remove-Module -Name 'Whiskey' -Force
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
    $script:testRoot = New-WhiskeyTestRoot
}

function ThenError
{
    param(
        $Matches
    )

    $Global:Error | Should -Match $Matches
}

function ThenFailed
{
    $failed | Should -BeTrue
}

function ThenFile
{
    param(
        $Name,
        [switch]$Exists
    )

    Join-Path -Path $testRoot -ChildPath $Name | Should -Exist
}

function ThenTask
{
    param(
        $Name,
        [switch]$Exists
    )

    Get-WhiskeyTask | Where-Object { $_.Name -eq $Name } | Should -Not -BeNullOrEmpty
}

function WhenLoading
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()
    try
    {
        [Whiskey.Context]$context = New-WhiskeyTestContext -ForDeveloper `
                                                           -ConfigurationPath (Join-Path -Path $testRoot -ChildPath 'whiskey.yml') `
                                                           -ForBuildRoot $testRoot
        $parameter =
            $context.Configuration['Build'] |
            Where-Object { $_.ContainsKey('LoadTask') } |
            ForEach-Object { $_['LoadTask'] }

        Invoke-WhiskeyTask -TaskContext $context -Name 'LoadTask' -Parameter $parameter
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'LoadTask.when loading a task' {
    It 'should load the task' {
        Init
        GivenFile task.ps1 @'
    function script:MyTask
    {
        [Whiskey.Task('Fubar')]
        param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter        
        )
    }
'@
        GivenFile 'whiskey.yml' @'
    Build:
    - LoadTask:
        Path: task.ps1
'@
        WhenLoading
        ThenTask 'Fubar' -Exists
    }
}

Describe 'LoadTask.when scoped incorrectly' {
    It 'should fail' {
        Init
        GivenFile task.ps1 @'
    function MyTask
    {
        [Whiskey.Task('Fubar')]
        param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter        
        )
    }
'@
        GivenFile 'whiskey.yml' @'
    Build:
    - LoadTask:
        Path: task.ps1
'@
        WhenLoading -ErrorAction SilentlyContinue
        ThenFailed
        ThenError -Matches 'is\ scoped\ correctly'
    }
}

Describe 'LoadTask.when running custom tasks in the Parallel task' {
    It 'should re-import tasks in the background' {
        Init
        GivenFile task.ps1 @'
    function script:MyTask
    {
        [Whiskey.Task('Fubar')]
        param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter        
        )

        New-Item -Path 'fubar' -ItemType 'File'
    }
'@
        GivenFile 'whiskey.yml' @'
    Build:
    - LoadTask:
        Path: task.ps1
    - Parallel:
        Queues:
        - Tasks:
            - Fubar
'@
        $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')
        Invoke-WhiskeyBuild -Context $context
        ThenFile 'fubar' -Exists
    }
}

Describe 'LoadTask.when loading the same tasks multiple times' {
    It 'should use the last task' {
        Init
        GivenFile task.ps1 @'
    function script:MyTask
    {
        [Whiskey.Task('Fubar')]
        param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter        
        )
    }
'@
        GivenFile 'whiskey.yml' @'
    Build:
    - LoadTask:
        Path: task.ps1
    - LoadTask:
        Path: task.ps1
'@
        $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')
        Invoke-WhiskeyBuild -Context $context
        ThenTask 'Fubar' -Exists
    }
}