
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestTaskModule

Describe 'Get-WhiskeyTasks' {
    It 'should return task objects' {
        
        $expectedTasks = @{}
        foreach( $cmd in (Get-Command -Module 'WhiskeyTestTasks') )
        {
            if( $cmd.Name -like 'DuplicateTask*' )
            {
                continue
            }

            $taskName = ''
            foreach( $attr in $cmd.ScriptBlock.Attributes )
            {
                if( $attr -is [Whiskey.TaskAttribute] )
                {
                    $expectedTasks[$attr.Name] = $attr
                    break
                }
            }
        }

        $expectedTasks.Keys | Should -Not -BeNullOrEmpty

        $Global:error.Clear()
        $failed = $false
        $tasks = @()
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
                $task.CommandName | Should -Be $expectedTasks[$task.Name].CommandName
            }
        }

        foreach( $taskName in $expectedTasks.Keys )
        {
            $expectedTask = $expectedTasks[$taskName]
            $actualTask = $tasks | Where-Object { $_.Name -eq $taskName } 

            if( $expectedTask.Obsolete )
            {
                $actualTask | Should -BeNullOrEmpty -Because ('should return "{0}" task' -f $taskName)
            }
            else
            {
                $actualTask | Should -Not -BeNullOrEmpty -Because ('should not return obsolete "{0}" task' -f $taskName)
            }
        }

        $tasks | Where-Object { $_.Obsolete } | Should -BeNullOrEmpty

        $tasks = Get-WhiskeyTask -Force
        $tasks | Where-Object { $_.Obsolete } | Should -Not -BeNullOrEmpty


        foreach( $taskName in $expectedTasks.Keys )
        {
            $expectedTask = $expectedTasks[$taskName]
            $actualTask = $tasks | Where-Object { $_.Name -eq $taskName } | Should -Not -BeNullOrEmpty -Because ('should return all tasks when using the Force')
        }
    }
}
