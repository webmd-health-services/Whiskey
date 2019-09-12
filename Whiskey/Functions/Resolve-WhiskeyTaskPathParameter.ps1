function Resolve-WhiskeyTaskPathParameter
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # An object that holds context about the current build and executing task.
        [Whiskey.Context]$TaskContext,

        [Parameter(ValueFromPipeline)]
        [string]$Path,

        [Parameter(Mandatory)]
        [Management.Automation.ParameterMetadata]$CmdParameter,

        [Parameter(Mandatory)]
        [Whiskey.Tasks.ValidatePathAttribute]$ValidateAsPathAttribute
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

        if( -not $Path )
        {
            if( $ValidateAsPathAttribute.Mandatory )
            {
                Stop-WhiskeyTask -TaskContext $Context `
                                 -PropertyName $CmdParameter.Name `
                                 -Message ('{0} is mandatory.' -f $CmdParameter.Name)
                return
            }
            return     
        }

        if( -not [IO.Path]::IsPathRooted($Path) )
        {
            $Path = Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
        }

        $optionalParams = @{}
        if( $ValidateAsPathAttribute.AllowNonexistent )
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
            if( -not $ValidateAsPathAttribute.AllowNonexistent )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext `
                                 -Message ('{0}[{1}] "{2}" does not exist.' -f $CmdParameter.Name,$pathIdx,$Path)
                return
            }
            $result = [IO.Path]::GetFullPath($Path)

            if( [Management.Automation.WildCardPattern]::ContainsWildcardCharacters($result) )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext `
                                 -Message ('{0}[{1}] "{2}" did not resolve to anything.' -f $CmdParameter.Name,$pathIdx,$Path)
            }
        }

            
        if( -not $ValidateAsPathAttribute.AllowOutsideBuildRoot )
        {
            $fsCaseSensitive = -not (Test-Path -Path ($TaskContext.BuildRoot.FullName.ToUpperInvariant()))
            $normalizedBuildRoot = $TaskContext.BuildRoot.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $normalizedBuildRoot = '{0}{1}' -f $normalizedBuildRoot,[IO.Path]::DirectorySeparatorChar

            $comparer = [System.StringComparison]::OrdinalIgnoreCase
            if( $fsCaseSensitive )
            {
                $comparer = [System.StringComparison]::Ordinal
            }
            
            $invalidPaths =
                $result |
                Where-Object { -not ( $_.StartsWith($normalizedBuildRoot, $comparer) ) }

            if( $invalidPaths )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext `
                                 -Message ('{0}[{1}] "{2}" is outside the build root "{3}".' -f $CmdParameter.Name,$pathIdx,$Path,$TaskContext.ConfigurationPath)
                return
            }
        }

        $expectedPathType = $ValidateAsPathAttribute.PathType  
        if( $expectedPathType -and -not $ValidateAsPathAttribute.AllowNonexistent )
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
                Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName $CmdParameter.Name -Message (@'
Found {1} paths that should be to a {0}, but aren''t:

* {2}

'@ -f $expectedPathType.ToLowerInvariant(),($invalidPaths | Measure-Object).Count,($invalidPaths -join ('{0}* ' -f [Environment]::NewLine)))
                return
            }
        }

        $pathCount = $result | Measure-Object | Select-Object -ExpandProperty 'Count'
        if( $CmdParameter.ParameterType -ne ([string[]]) -and $pathCount -gt 1 )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName $CmdParameter.Name -Message (@'
The value "{1}" resolved to {2} paths [1] but this task requires a single path. Please change "{1}" to a value that resolves to a single item.

If you are this task''s author, and you want this property to accept multiple paths, please update the "{3}" command''s "{0}" property so it''s type is "[string[]]".

[1] The {1} path resolved to:

* {4}

'@ -f $CmdParameter.Name,$Path,$pathCount,$TaskContext.TaskName,($result -join ('{0}* ' -f [Environment]::NewLine)))
        }

        return $result
    }

    end
    {
    }
}