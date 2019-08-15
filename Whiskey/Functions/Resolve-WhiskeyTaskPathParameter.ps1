function Resolve-WhiskeyTaskPathParameter
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # An object that holds context about the current build and executing task.
        $TaskContext,

        [Parameter(ValueFromPipeline=$true)]
        [string]
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        $PropertyName,

        [Parameter(Mandatory=$true)]
        [Management.Automation.ParameterMetadata]
        $CmdParameter,

        [Parameter(Mandatory=$true)]
        [Whiskey.Tasks.ValidatePathAttribute]
        $ValidateAsPathAttr
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

        $result = $Path

        if( -not $Path -and $ValidateAsPathAttr.Mandatory )
        {
            $errorMsg = 'path is mandatory.' -f $TaskProperty[$propertyName]
            Stop-WhiskeyTask -TaskContext $Context -PropertyName $CmdParameter.Name -Message $errorMsg
        }

        if( $Path )
        {
            if( [IO.Path]::IsPathRooted($Path) -and -not $ValidateAsPathAttr.AllowAbsolute )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' is absolute but must be relative to the ''{3}'' file.' -f $PropertyName,$pathIdx,$Path,$TaskContext.ConfigurationPath)
                return
            }

            if( -not [IO.Path]::IsPathRooted($Path) )
            {
                $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
            }

            $optionalParams = @{}
            if( -not $ValidateAsPathAttr.MustExist)
            {
                $optionalParams['ErrorAction'] = 'Ignore'
            }

            $message = 'Resolve {0} ->' -f $result
            $prefix = ' ' * ($message.Length - 3)
            Write-Debug -Message $message
            $result = 
                Resolve-Path -Path $Path @optionalParams | 
                Select-Object -ExpandProperty 'ProviderPath' |
                ForEach-Object { 
                    Write-Debug -Message ('{0} -> {1}' -f $prefix,$_)
                    $_
                }

            if( -not $result ) 
            {
                if( $ValidateAsPathAttr.MustExist -or [WildcardPattern]::ContainsWildcardCharacters( $Path ) )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' does not exist and must exist.' -f $PropertyName,$pathIdx,$Path,$TaskContext.ConfigurationPath)
                    return
                }
                $result = [IO.Path]::GetFullPath($Path)
            }
                
            if( -not $ValidateAsPathAttr.AllowOutsideBuildRoot )
            {
                $normalizedBuildRoot = $TaskContext.BuildRoot.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                $normalizedBuildRoot = '{0}{1}' -f $normalizedBuildRoot,[IO.Path]::DirectorySeparatorChar
                
                $invalidPaths =
                    $result |
                    Where-Object { -not ( $_.StartsWith($normalizedBuildRoot) ) }

                if( $invalidPaths )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0}[{1}] ''{2}'' is outside of the build root and not allowed to be.' -f $PropertyName,$pathIdx,$Path,$TaskContext.ConfigurationPath)
                    return
                }
            }
        }

        $expectedPathType = $validateAsPathAttr.PathType  
        if( $result -and $expectedPathType -and $validateAsPathAttr.MustExist )
        {
            $pathType = 'Leaf'
            if( $expectedPathType -eq 'Directory' )
            {
                $pathType = 'Container'
            }
            $invalidPaths = 
                $result | 
                Where-Object { -not (Test-Path -Path $_ -PathType $pathType) }
            if( $invalidPaths )
            {
                Stop-WhiskeyTask -TaskContext $Context -PropertyName $cmdParameter.Name -Message (@'
must be a {0}, but found {1} path(s) that are not:

* {2}

'@ -f $expectedPathType.ToLowerInvariant(),($invalidPaths | Measure-Object).Count,($invalidPaths -join ('{0}* ' -f [Environment]::NewLine)))
            }
        }

        $pathCount = $result | Measure-Object | Select-Object -ExpandProperty 'Count'
        if( $cmdParameter.ParameterType -ne ([string[]]) -and $pathCount -gt 1 )
        {
            Stop-WhiskeyTask -TaskContext $Context -PropertyName $cmdParameter.Name -Message (@'
The value "{1}" resolved to {2} paths [1] but this task requires a single path. Please change "{1}" to a value that resolves to a single item.

If you are this task''s author, and you want this property to accept multiple paths, please update the "{3}" command''s "{0}" property so it''s type is "[string[]]".

[1] The {1} path resolved to:

* {4}

'@ -f $cmdParameter.Name,$TaskProperty[$propertyName],$pathCount,$task.CommandName,($result -join ('{0}* ' -f [Environment]::NewLine)))
        }

        return $result
    }

    end
    {
    }
}