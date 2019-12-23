
function Import-WhiskeyTask
{
    [Whiskey.Task('LoadTask')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $module = Get-Module -Name 'Whiskey'
    foreach( $pathItem in $Path )
    {
        $fullPathItem = Resolve-Path -Path $pathItem | Select-Object -ExpandProperty 'ProviderPath'
        if( $TaskContext.TaskPaths | Where-Object { $_.FullName -eq $fullPathItem } )
        {
            Write-WhiskeyVerbose -Context $TaskContext -Message ('Already loaded tasks from file "{0}".' -f $pathItem)
            continue
        }

        $knownTasks = @{}
        Get-WhiskeyTask | ForEach-Object { $knownTasks[$_.Name] = $_ }
        # We do this in a background script block to ensure the function is scoped correctly. If it isn't, it
        # won't be available outside the script block. If it is, it will be visible after the script block completes.
        & {
            . $pathItem
        }
        $newTasks = Get-WhiskeyTask | Where-Object { -not $knownTasks.ContainsKey($_.Name) }
        if( -not $newTasks )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('File "{0}" contains no Whiskey tasks. Make sure:

* the file contains a function
* the function is scoped correctly (e.g. `function script:MyTask`)
* the function has a `[Whiskey.Task(''MyTask'')]` attribute that declares the task''s name
* a task with the same name hasn''t already been loaded

See about_Whiskey_Writing_Tasks for more information.' -f $pathItem)
            return
        }

        Write-WhiskeyInfo -Context $TaskContext -Message ($pathItem)
        foreach( $task in $newTasks )
        {
            Write-WhiskeyInfo -Context $TaskContext -Message ('  {0}' -f $task.Name)
        }
        $TaskContext.TaskPaths.Add((Get-Item -Path $pathItem))
    }
}
