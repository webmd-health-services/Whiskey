
function Invoke-WhiskeyPowerShell
{
    [Whiskey.Task("PowerShell")]
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
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of PowerShell Scripts to run, e.g. 
        
            BuildTasks:
            - PowerShell:
                Path:
                - myscript.ps1
                - myotherscript.ps1
                WorkingDirectory: bin')
        }
    
    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'

    if( $TaskParameter.ContainsKey('WorkingDirectory') )
    {
        if( -not [IO.Path]::IsPathRooted($TaskParameter['WorkingDirectory']))
        {
            $workingDirectory = $TaskParameter['WorkingDirectory'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'WorkingDirectory'
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
    if( -not $argument )
    {
        $argument = @{ }
    }

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
            & $ScriptPath -TaskContext $TaskContext @argument
            if( $Global:LASTEXITCODE )
            {
                throw ('PowerShell script ''{0}'' failed, exited with code {1}.' -F $ScriptPath,$Global:LASTEXITCODE)
            }
        }
        finally
        {
            Pop-Location
        }
    }
}
