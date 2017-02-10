
function Resolve-WhsCITaskPath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # An object that holds context about the current build and executing task.
        $TaskContext,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        $PropertyName
    )

    begin
    {
        Set-StrictMode -Version 'Latest'

        $pathIdx = -1
    }

    process
    {
        Set-StrictMode -Version 'Latest'

        $pathIdx++

        if( [IO.Path]::IsPathRooted($Path) )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' is absolute but must be relative to the ''{3}'' file.' -f $PropertyName,$pathIdx,$Path,$TaskContext.ConfigurationPath)
            return
        }

        $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
        if( -not (Test-Path -Path $Path) )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' does not exist.' -f $PropertyName,$pathIdx,$Path)
        }

        Resolve-Path -Path $Path | Select-Object -ExpandProperty 'ProviderPath'
    }

    end
    {
    }
}

