
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
$taskContext = $null

function Init
{
    $script:failed = $false
    $script:taskContext = $null
}

function ThenContextStopPropertyIsTrue
{
    It 'should set the task context''s "Stop" property to True' {
        $taskContext.Stop | Should -BeTrue
    }
}

function ThenTaskSuccess
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'task should succeed' {
        $failed | Should -BeFalse
    }
}

function WhenRunningStopTask
{
    $script:taskContext = New-WhiskeyTestContext -ForDeveloper

    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter @{ } -Name 'Stop'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Stop.when running Stop task' {
    Init
    WhenRunningStopTask
    ThenContextStopPropertyIsTrue
    ThenTaskSuccess
}
