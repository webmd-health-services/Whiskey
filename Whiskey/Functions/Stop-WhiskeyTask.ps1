
function Stop-WhiskeyTask
{
    <#
    .SYNOPSIS
    Fails a Whiskey build by writing a terminating exception.

    .DESCRIPTION
    The `Stop-WhiskeyTask` function fails the current task and build by writing a terminating exception. Pass the current task's context to the `TaskContext` parameter. Pass a failure message to the `Message` property. Whiskey will fail the build with an error message that explans what task in what whiskey.yml file failed.

    If your build is failing because a task property is invalid, pass the name of the property to the `PropertyName` parameter. The property's name will be inserted into the error message.

    If you want to customize the task description in the error message, pass that description to the `PropertyDescription` parameter. Instead of using 'Task "TASK_NAME"' in the error message, Whiskey will use the value of the PropertyDescription parameter.

    .EXAMPLE
    Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Something bad happened!'

    Demonstrates how to fail and stop the current build with the message "Something bad happened!".

    .EXAMPLE
    Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Must be a number.' -PropertyName 'Count'

    Demonstrates how to add the name of an invalid property to the error message. The result of this example will be to have an error message like 'whiskey.yml: Task "MyTask": Property "Count": Must be a number.'

    .EXAMPLE
    Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Bad things!' -PropertyDescription '"Fubar" task's "Snafu" property'

    Demonstrates how to customize the task name portion of the error message. In this case, Whiskey will write an error message like 'whiskey.yml: "Fubar" task's "Snafu" property: Bad things!'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [String]$Message,

        [String]$PropertyName,

        [String]$PropertyDescription
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( -not ($PropertyDescription) )
    {
        $PropertyDescription = 'Task "{0}"' -f $TaskContext.TaskName
    }

    if( $PropertyName )
    {
        $PropertyName = ': Property "{0}"' -f $PropertyName
    }

    if( $ErrorActionPreference -ne 'Ignore' )
    {
        $message = '{0}: {1}{2}: {3}' -f $TaskContext.ConfigurationPath,$PropertyDescription,$PropertyName,$Message
        Write-WhiskeyError -Context $TaskContext -Message $message -ErrorAction Stop
    }
}
