
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

    it 'should not fail' {
        $failed | should be $false
    }
    it 'should not write error' {
        $Global:error | should beNullOrEmpty
    }

    it 'should return the right number of WhiskeyTasks' {
        $tasks.Count | should -BeGreaterThan ($expectedTasks.Count - 1)
    }

    It ('should return the attribute') {
        $tasks | Should -BeOfType ([Whiskey.TaskAttribute])
    }

    foreach( $task in $tasks )
    {
        if( $expectedTasks.ContainsKey($task.Name) )
        {
            it ('it should return the {0} task' -f $task.Name) {
                $task.CommandName | should -Be $expectedTasks[$task.Name]
            }
        }
    }

    It ('should not return obsolete tasks') {
        $tasks | Where-Object { $_.Obsolete } | Should -BeNullOrEmpty
    }

    $tasks = Get-WhiskeyTask -Force
    It ('should return obsolete tasks when forced to do so') {
        $tasks | Where-Object { $_.Obsolete } | Should -Not -BeNullOrEmpty
    }

}

Remove-Item -Path 'function:MyTask*'