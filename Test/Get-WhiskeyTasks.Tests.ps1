
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
                        TAskThree = 'MyTask2';
                        }

    $Global:error.Clear()
    $failed = $false
    try
    {
        $tasks = Get-WhiskeyTasks
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
         $expectedTasks.Count 
    }

    foreach ($key in $expectedTasks.keys)
    {
        it ('it should return the {0} task' -f $key) {
            $tasks[$key] | should be $expectedTasks[$key]
        }
    }


}

Remove-Item -Path 'function:MyTask*'