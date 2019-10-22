
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function global:MyTask
{
    [Whiskey.Task("TaskOne")]
    param(
    )
}

function global:MyTask2
{
    [Whiskey.Task("TaskTwo")]
    [Whiskey.Task("TaskThree")]
    param(
    )
}

function global:MyObsoleteTask
{
    [Whiskey.Task("TaskTwo",Obsolete)]
    param(
    )
}

Describe 'Get-WhiskeyTasks' {
    It 'should return task objects' {
        $expectedTasks = @{
                            ProGetUniversalPackage         = 'New-WhiskeyProGetUniversalPackage';
                            MSBuild                        = 'Invoke-WhiskeyMSBuild';
                            NUnit2                         = 'Invoke-WhiskeyNUnit2Task';
                            Node                           = 'Invoke-WhiskeyNodeTask';
                            Pester3                        = 'Invoke-WhiskeyPester3Task';
                            Pester4                        = 'Invoke-WhiskeyPester4Task';
                            PublishFile                    = 'Publish-WhiskeyFile';
                            PublishNodeModule              = 'Publish-WhiskeyNodeModule';
                            PublishPowerShellModule        = 'Publish-WhiskeyPowerShellModule';
                            TaskOne = 'MyTask';
                            TaskTwo = 'MyTask2';
                            TaskThree = 'MyTask2';
                        }

        $Global:error.Clear()
        $failed = $false
        try
        {
            $tasks = Get-WhiskeyTask
        }
        catch
        {
            $failed = $true
        }

        $failed | Should -BeFalse
        $Global:error | Should -BeNullOrEmpty
        $tasks.Count | Should -BeGreaterThan ($expectedTasks.Count - 1)
        $tasks | Should -BeOfType ([Whiskey.TaskAttribute])

        foreach( $task in $tasks )
        {
            if( $expectedTasks.ContainsKey($task.Name) )
            {
                $task.CommandName | should -Be $expectedTasks[$task.Name]
            }
        }

        $tasks | Where-Object { $_.Obsolete } | Should -BeNullOrEmpty

        $tasks = Get-WhiskeyTask -Force
        $tasks | Where-Object { $_.Obsolete } | Should -Not -BeNullOrEmpty
    }
}

Remove-Item -Path 'function:MyTask*'