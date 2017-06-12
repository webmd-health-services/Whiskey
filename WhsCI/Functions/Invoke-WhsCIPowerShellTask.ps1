
function Invoke-WhsCIPowerShellTask
{
    <#
    .SYNOPSIS
    Runs PowerShell commands.

    .DESCRIPTION
    The `Invoke-WhsCIPowerShellTask` runs PowerShell scripts. Pass the path to the script to the `TaskParameter[''Path'']` parameter. IF the script exists with a non-zero exit code, the task fails (i.e. throws a terminating exception/error).
    
    You can pecify an explicit working directory with a `TaskParameter['WorkingDirectory']` element.

    You *must* include paths to the scripts to run with the `Path` parameter.

    .EXAMPLE
    Invoke-WhsCIPowerShellTask -TaskContext $context -TaskParameter $TaskParameter

    Demonstrates how to use the `Invoke-WhsCIPowerShellTask` function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter,

        [Switch]
        $Clean
    )
    
    Set-StrictMode -Version 'Latest'
    if( $Clean )
    {
        return
    }
    
    if( -not ($TaskParameter.ContainsKey('Path')))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of PowerShell Scripts to run, e.g. 
        
            BuildTasks:
            - PowerShell:
                Path:
                - myscript.ps1
                - myotherscript.ps1
                WorkingDirectory: bin')
        }
    
    $path = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'

    if( $TaskParameter.ContainsKey('WorkingDirectory') )
    {
        if( -not [IO.Path]::IsPathRooted($TaskParameter['WorkingDirectory']))
        {
            $workingDirectory = $TaskParameter['WorkingDirectory'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory'
        } 
        else
        {
            $workingDirectory = $TaskParameter['WorkingDirectory']
        }       
    }
    else
    {
        $WorkingDirectory = $TaskContext.BuildRoot
    }

    $argument = $TaskParameter['Argument']

    foreach( $scriptPath in $path )
    {

        if( -not (Test-Path -Path $WorkingDirectory -PathType Container) )
        {
            throw ('Can''t run PowerShell script ''{0}'': working directory ''{1}'' doesn''t exist.' -f $ScriptPath,$WorkingDirectory)
        }

        Push-Location $WorkingDirectory
        try
        {
            $Global:LASTEXITCODE = 0
            & $ScriptPath @argument
            if( $Global:LASTEXITCODE )
            {
                throw ('PowerShell script ''{0}'' failed, exiting with code {1}.' -F $ScriptPath,$Global:LASTEXITCODE)
            }
        }
        finally
        {
            Pop-Location
        }
    }
}