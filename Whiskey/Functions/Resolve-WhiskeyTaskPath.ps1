
function Resolve-WhiskeyTaskPathInternal
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # An object that holds context about the current build and executing task.
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory,ValueFromPipeline)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$PropertyName,

        # The root directory to use when resolving paths. The default is to use the `$TaskContext.BuildRoot` directory. Each path must be relative to this path.
        [String]$ParentPath,

        # Create the path if it doesn't exist. By default, the path will be created as a directory. To create the path as a file, pass `File` to the `PathType` parameter.
        [switch]$Force,

        [ValidateSet('Directory','File')]
        # The type of item to create when using the `Force` parameter to create paths that don't exist. The default is to create the path as a directory. Pass `File` to create the path as a file.
        [String]$PathType = 'Directory'
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

        $originalPath = $Path
        if( [IO.Path]::IsPathRooted($Path) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' is absolute but must be relative to the ''{3}'' file.' -f $PropertyName,$pathIdx,$Path,$TaskContext.ConfigurationPath)
            return
        }

        if( -not $ParentPath )
        {
            $ParentPath = $TaskContext.BuildRoot
        }

        $Path = Join-Path -Path $ParentPath -ChildPath $Path
        if( -not (Test-Path -Path $Path) )
        {
            if( $Force )
            {
                New-Item -Path $Path -ItemType $PathType -Force | Out-String | Write-WhiskeyDebug -Context $TaskContext
            }
            else
            {
                if( $ErrorActionPreference -ne [Management.Automation.ActionPreference]::Ignore )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0}[{1}] "{2}" does not exist.' -f $PropertyName,$pathIdx,$Path)
                }
                return
            }
        }

        $message = 'Resolve {0} ->' -f $originalPath
        $prefix = ' ' * ($message.Length - 3)
        Write-WhiskeyDebug -Context $TaskContext -Message $message
        Resolve-Path -Path $Path | 
            Select-Object -ExpandProperty 'ProviderPath' |
            ForEach-Object { 
                Write-WhiskeyDebug -Context $TaskContext -Message ('{0} -> {1}' -f $prefix,$_)
                $_
            }
    }

    end
    {
    }
}


