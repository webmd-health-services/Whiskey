
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

Describe 'Get-WhiskeyTasks' {
    $expectedTasks = @{
                        ProGetUniversalPackage         = 'Invoke-WhiskeyProGetUniversalPackageTask';
                        MSBuild                        = 'Invoke-WhiskeyMSBuildTask';
                        NUnit2                         = 'Invoke-WhiskeyNUnit2Task';
                        Node                           = 'Invoke-WhiskeyNodeTask';
                        Pester3                        = 'Invoke-WhiskeyPester3Task';
                        Pester4                        = 'Invoke-WhiskeyPester4Task';
                        PublishFile                    = 'Invoke-WhiskeyPublishFileTask';
                        PublishNodeModule              = 'Invoke-WhiskeyPublishNodeModuleTask';
                        PublishPowerShellModule        = 'Invoke-WhiskeyPublishPowerShellModuleTask';
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


}

Remove-Item -Path 'function:MyTask*'