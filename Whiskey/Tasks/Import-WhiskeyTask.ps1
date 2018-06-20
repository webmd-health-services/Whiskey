    
function Import-WhiskeyTask
{
    [Whiskey.Task("LoadTasks")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $module = Get-Module -Name 'Whiskey'
    $paths = Resolve-WhiskeyTaskPath -TaskContext $TaskContext -Path $TaskParameter['Path'] -PropertyName 'Path'
    $newTasks = New-Object 'Collections.ArrayList'
    foreach( $path in $paths )
    {
        $knownTasks = @{}
        Get-WhiskeyTask | ForEach-Object { $knownTasks[$_.Name] = $_ }
        . $path
        $newTasks = Get-WhiskeyTask | Where-Object { -not $knownTasks.ContainsKey($_.Name) }
        if( -not $newTasks )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('File "{0}" contains no Whiskey tasks. Make sure:
 
* the file contains a function
* the function is scoped correctly (e.g. `function script:MyTask`)
* the function has a `[Whiskey.Task("MyTask")]` attribute that declares the task''s name
 
See about_Whiskey_Writing_Tasks for more information.' -f $path)
        }
        Write-WhiskeyInfo -Context $TaskContext -Message ($path)
        foreach( $task in $newTasks )
        {
            Write-WhiskeyInfo -Context $TaskContext -Message $task.Name -Indent 1
        }
        $TaskContext.TaskPaths.Add((Get-Item -Path $path))
    }
}
