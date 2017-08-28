function Invoke-WhiskeyProcess
{
    <#
    .SYNOPSIS
    Starts a process with given arguments
    
    .DESCRIPTION
    The `Process` task runs an executable located at a given `Path`, relative to your `whiskey.yml` file. Additionally, you may specify a list of `Argument` and a `WorkingDirectory` in which to start the process.
    
    The exit code for the process must be '0' or one of `SuccessExitCode` specified, otherwise the build will be failed.
    
    ## Properties

    ### Mandatory
    * `Path`: path to the executable to run, relative to `whiskey.yml`
    
    ### Optional
    * `Argument`: a list of arguments to be passed to the executable
    * `SuccessExitCode`: a list of exit codes that indicate the process ran successfully
    * `WorkingDirectory`: the directory in which to start the process

    ## Examples

    ### Example 1

        BuildTasks:
        - Process:
            Path: NCrunch.exe
            Argument:
            - Fubar
            - Snafu
            WorkingDirectory: .
            SuccessExitCode:
            - 0
            - 1
            - 2

    This example would launch the 'NCrunch.exe', located in the root directory of `whiskey.yml`, with the arguments 'Fubar' and 'Snafu'.
    
    The `WorkingDirectory` for the process would be the root build directory and the process must return an exit code of 0, 1, or 2 for the build to not fail.
    #>      

    [CmdletBinding()]
    [Whiskey.Task("Process")]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $path = $TaskParameter['Path']
    if ( -not $path )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Path'' is mandatory. It should be the Path to the executable you want to start the Process with.')
    }

    $processPath = ''
    if ( Test-Path -Path $path -PathType Leaf )
    {
        $processPath = Resolve-Path -Path $path | Select-Object -ExpandProperty Path
    }
    elseif ( Get-Command -Name $path -CommandType Application -ErrorAction Ignore )
    {
        $processPath = $path
    }

    if ( $processPath -eq '' )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Could not locate the executable file ''{0}'' specified in the ''Path'' property.' -f $path)
    }


    $workingDirectory = $processPath | Split-Path
    if ( $TaskParameter['WorkingDirectory'] )
    {
        $workingDirectory = $TaskParameter['WorkingDirectory']

        if ( -not (Test-Path -Path $workingDirectory -PathType Container) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Could not locate the directory ''{0}'' specified in the ''WorkingDirectory'' property.' -f $workingDirectory)
        }
    }
    elseif ( $workingDirectory -eq '' )
    {
        $workingDirectory = $TaskContext.BuildRoot
    }


    $argumentListParam = @{}
    if ( $TaskParameter['Argument'] )
    {
        $argumentListParam['ArgumentList'] = $TaskParameter['Argument']
    }


    $successExitCode = 0
    if ( $TaskParameter['SuccessExitCode'] )
    {
        $successExitCode = $TaskParameter['SuccessExitCode']
    }


    $process = Start-Process -FilePath $processPath @argumentListParam -WorkingDirectory $workingDirectory -NoNewWindow -Wait -PassThru

    $exitCode = $process.ExitCode
    if ( $exitCode -notin $successExitCode )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('''{0}'' returned with an exit code of ''{1}'', which is not one of the expected ''SuccessExitCode'' of ''{2}''.' -F $TaskParameter['Path'],$exitCode,$successExitCode -join ',')
    }

}