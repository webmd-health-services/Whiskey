
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false

function GivenFile
{
    param(
        $Path,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path)
}

function Init
{
    $script:failed = $false
}

function ThenError
{
    param(
        $Matches
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Matches
    }
}

function ThenFailed
{
    It ('should fail') {
        $failed | Should -BeTrue
    }
}

function ThenFile
{
    param(
        $Name,
        [Switch]
        $Exists
    )

    It ('should load task') {
        Join-Path -Path $TestDrive.FullName -ChildPath $Name | Should -Exist
    }
}

function ThenTask
{
    param(
        $Name,
        [Switch]
        $Exists
    )

    It ('should load task') {
        Get-WhiskeyTask | Where-Object { $_.Name -eq $Name } | Should -Not -BeNullOrEmpty
    }
}

function WhenLoading
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()
    try
    {
        [Whiskey.Context]$context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
        $parameter = $context.Configuration['Build'] | Where-Object { $_.ContainsKey('LoadTasks') } | ForEach-Object { $_['LoadTasks'] }
        Invoke-WhiskeyTask -TaskContext $context -Name 'LoadTasks' -Parameter $parameter
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'LoadTasks' {
    Init
    GivenFile task.ps1 @'
function script:MyTask
{
    [Whiskey.Task('Fubar')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter        
    )
}
'@
    GivenFile 'whiskey.yml' @'
Build:
- LoadTasks:
    Path: task.ps1
'@
    WhenLoading
    ThenTask 'Fubar' -Exists
}

Describe 'LoadTasks.when scoped incorrectly' {
    Init
    GivenFile task.ps1 @'
function MyTask
{
    [Whiskey.Task('Fubar')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter        
    )
}
'@
    GivenFile 'whiskey.yml' @'
Build:
- LoadTasks:
    Path: task.ps1
'@
    WhenLoading -ErrorAction SilentlyContinue
    ThenFailed
    ThenError -Matches 'is\ scoped\ correctly'
}

Describe 'LoadTasks.when running custom tasks in the Parallel task' {
    Init
    GivenFile task.ps1 @'
function script:MyTask
{
    [Whiskey.Task('Fubar')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter        
    )

    New-Item -Path 'fubar' -ItemType 'File'
}
'@
    GivenFile 'whiskey.yml' @'
Build:
- LoadTasks:
    Path: task.ps1
- Parallel:
    Queues:
    - Tasks:
        - Fubar
'@
    $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
    Invoke-WhiskeyBuild -Context $context 
    ThenFile 'fubar' -Exists
}