
function Resolve-WhiskeyTaskPath
{
    <#
    .SYNOPSIS
    Resolves paths provided by users to actual paths tasks can use.

    .DESCRIPTION
    The `Resolve-WhiskeyTaskPath` function validates and resolves paths provided by users to actual paths. It:

    * ensures the paths exist (use the `AllowNonexistent` switch to allow paths that don't exist).
    * can ensure the user provides at least one value (use the `Mandatory` switch).
    * can ensure the user only provides one path or one path that resolves to a single path (use the `OnlySinglePath`
      switch).
    * can ensure that the user provides a path to a file or directory (pass the type you want to the `PathType`
      parameter).
    * can create the paths the user passed in (use the `Create` switch, the `AllowNonexistent` switch, and the
      `PathType` parameters).

    Wildcards are accepted for all paths and are resolved to actual paths.

    Paths are resolved relative to the current working directory, which for a Whiskey task is the build directory.

    You must pass the name of the property whose path you're resolving to the `ProperytName` parameter. This is so
    Whiskey can write friendly error messages to the user.

    The resolved, relative paths are returned.

    If paths don't exist, Whiskey will stop and fail the current build. To allow paths to not exist, use the
    `AllowNonexistent` switch.

    You can use glob patterns (e.g. `**`) to find files. Pass your patterns to the `Path` parameter and use the
    `UseGlob` switch. The function installs and uses the [Glob](https://www.powershellgallery.com/packages/Glob)
    PowerShell module to resolve the patterns to files.

    .LINK
    https://www.powershellgallery.com/packages/Glob

    .EXAMPLE
    $paths | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path'

    Demonstrates the simplest way to use `Resolve-WhiskeyTaskPath`.

    .EXAMPLE
    $paths | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -Mandatory

    Demonstrates how to ensure that the user provides at least one path value to resolve.

    .EXAMPLE
    $path | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -OnlySinglePath

    Demonstrates how to ensure that the path(s) the user provides only resolves to one item.

    .EXAMPLE
    $path | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -PathType 'File'

    Demonstrates how to ensure that the user has passed paths to only files.

    .EXAMPLE
    $path | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -PathType 'Directory'

    Demonstrates how to ensure that the user has passed paths to only directories.

    .EXAMPLE
    $path | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -AllowNonexistent

    Demonstrates how to let the user pass paths to items that may or may not exist.

    .EXAMPLE
    $path | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'Path' -Create -AllowNonexistent -PathType File

    Demonstrates how to get Whiskey to create any non-existent items whose path the user passes. In this example,
    Whiskey will create files. To create directories, pass `Directory` to the PathType parameter. You *must* use
    `Create`, `AllowNonexistent`, and `PathType` parameters together.
    #>
    [CmdletBinding(DefaultParameterSetName='FromParameters')]
    param(
        [Parameter(Mandatory)]
        # An object that holds context about the current build and executing task.
        [Whiskey.Context]$TaskContext,

        [Parameter(ValueFromPipeline)]
        [String]$Path,

        [Parameter(Mandatory,ParameterSetName='FromAttribute')]
        # INTERNAL. DO NOT USE.
        [Management.Automation.ParameterMetadata]$CmdParameter,

        [Parameter(Mandatory,ParameterSetName='FromAttribute')]
        # INTERNAL. DO NOT USE.
        [Whiskey.Tasks.ValidatePathAttribute]$ValidatePathAttribute,

        [Parameter(Mandatory,ParameterSetName='FromAttribute')]
        # INTERNAL. DO NOT USE.
        [hashtable]$TaskParameter,

        [Parameter(Mandatory,ParameterSetName='FromParameters')]
        [Parameter(Mandatory,ParameterSetName='FromParametersUsingGlob')]
        # The name of the property from the user's whiskey.yml file being parsed. Used to output helpful error messages.
        [String]$PropertyName,

        [Parameter(ParameterSetName='FromParameters')]
        # Fail if the path does not resolve to a single path.
        [switch]$OnlySinglePath,

        [Parameter(ParameterSetName='FromParameters')]
        [Parameter(ParameterSetName='FromParametersUsingGlob')]
        # The `Path` parameter must have at least one value.
        [switch]$Mandatory,

        [Parameter(ParameterSetName='FromParameters')]
        [ValidateSet('File','Directory')]
        # The type of item the path should be.
        [String]$PathType,

        [Parameter(ParameterSetName='FromParameters')]
        # Allow the paths to not exist.
        [switch]$AllowNonexistent,

        [Parameter(ParameterSetName='FromParameters')]
        # Create the path if it doesn't exist. Requires the `PathType` parameter.
        [switch]$Create,

        [Parameter(Mandatory,ParameterSetName='FromParametersUsingGlob')]
        # Whether or not to use glob syntax to find files. Install and uses the
        # [Glob](https://www.powershellgallery.com/packages/Glob) PowerShell module to perform the search.
        [switch]$UseGlob,

        [Parameter(ParameterSetName='FromParametersUsingGlob')]
        # Files to exclude from being returned.
        [String[]]$Exclude = @()
    )

    begin
    {
        Set-StrictMode -Version 'Latest'

        $pathIdx = -1

        if( $PSCmdlet.ParameterSetName -eq 'FromAttribute' )
        {
            $Mandatory = $ValidatePathAttribute.Mandatory
            if( $ValidatePathAttribute.PathType )
            {
                $PathType = $ValidatePathAttribute.PathType
            }
            $AllowNonexistent = $ValidatePathAttribute.AllowNonexistent
            $Create = $ValidatePathAttribute.Create
            $UseGlob = $ValidatePathAttribute.UseGlob
            if( $ValidatePathAttribute.GlobExcludeParameter )
            {
                $Exclude = $TaskParameter[$ValidatePathAttribute.GlobExcludeParameter]
            }
            $PropertyName = $CmdParameter.Name
            $OnlySinglePath = $CmdParameter.ParameterType -ne [String[]]
            if( $UseGlob )
            {
                if( $OnlySinglePath )
                {
                    Stop-WhiskeyTask -TaskContext $Context -Message ('The "{0}" property is configured to use glob syntax to find matching paths, but the parameter''s type is not [String[]]. This is a task authoring error. If you are the task''s author, please change the "{0}" parameter''s type to be [String[]]. If you are not the task''s author, please contact them to request this change.' -f $PropertyName)
                    return
                }
            }
        }

        $useGetRelativePath = [IO.Path] | Get-Member -Static -Name 'GetRelativePath'

        $currentDirRelative = Join-Path -Path '..' -ChildPath (Get-Location | Split-Path -Leaf)
        $currentDir = (Get-Location).Path

        $globPaths = [Collections.ArrayList]::new()

        if( $UseGlob )
        {
            Install-WhiskeyPowerShellModule -Name 'Glob' -Version '0.1.*' -BuildRoot $TaskContext.BuildRoot -ErrorAction Stop |
                Out-Null
        }

        $insideCurrentDirPrefix = '.{0}' -f [IO.Path]::DirectorySeparatorChar
        $outsideCurrentDirPrefix = '..{0}' -f [IO.Path]::DirectorySeparatorChar

        # Carbon has a Resolve-RelativePath alias which is why we add a `W` prefix.
        function Resolve-WRelativePath
        {
            param(
                [Parameter(Mandatory)]
                [String[]]$Path,

                [String]$DebugPrefix
            )

            # Now, convert the paths to relative paths.
            foreach( $resolvedPath in $Path )
            {
                if( $useGetRelativePath )
                {
                    $relativePath = [IO.Path]::GetRelativePath($currentDir,$resolvedPath)
                    if( $relativePath -eq '.' )
                    {
                        $relativePath = '{0}{1}' -f $relativePath,[IO.Path]::DirectorySeparatorChar
                    }
                }
                else
                {
                    if( (Test-Path -Path $resolvedPath) )
                    {
                        $relativePath = Resolve-Path -Path $resolvedPath -Relative
                        # Resolve-Path likes to resolve the current directory's relative path as ..\DIR_NAME instead of .
                        if( $relativePath -eq $currentDirRelative )
                        {
                            $relativePath = '.{0}' -f [IO.Path]::DirectorySeparatorChar
                        }
                    }
                    else
                    {
                        # .NET Framework doesn't have a method to convert a non-existent path to a relative path, so we use
                        # P/Invoke to call into Windows shlwapi.
                        $relativePathBuilder = New-Object System.Text.StringBuilder 260
                        $converted = [Whiskey.Path]::PathRelativePathTo( $relativePathBuilder, $currentDir, [IO.FileAttributes]::Directory, $resolvedPath, [IO.FileAttributes]::Normal )
                        if( $converted )
                        {
                            $relativePath = $relativePathBuilder.ToString()
                        }
                        else
                        {
                            $relativePath = $resolvedPath
                        }
                    }
                }

                # Files/directories that begin with a period don't get the .\ or ./ prefix put on them.
                if( -not $relativePath.StartsWith($insideCurrentDirPrefix) -and -not $relativePath.StartsWith($outsideCurrentDirPrefix) )
                {
                    $relativePath = Join-Path -Path '.' -ChildPath $relativePath
                }

                if( $DebugPrefix )
                {
                    Write-WhiskeyDebug -Context $TaskContext -Message ('{0} -> {1}' -f $DebugPrefix,$relativePath)
                }
                Write-Output $relativePath
            }
        }
    }

    process
    {
        Set-StrictMode -Version 'Latest'

        $pathIdx++

        if( -not $Path )
        {
            if( $Mandatory )
            {
                Stop-WhiskeyTask -TaskContext $Context `
                                 -PropertyName $PropertyName `
                                 -Message ('{0} is mandatory.' -f $PropertyName)
                return
            }
            return
        }

        $result = $Path
        $resolvedPaths = $null

        # Normalize the directory separators, otherwise, if a path begins with '\', on Linux (and probably macOS),
        # `IsPathRooted` doesn't think the path is rooted.
        $normalizedPath = $result | Convert-WhiskeyPathDirectorySeparator

        if( $UseGlob )
        {
            if( [IO.Path]::IsPathRooted($normalizedPath) )
            {
                $normalizedPath = Resolve-WRelativePath -Path $normalizedPath
                if( $normalizedPath.StartsWith($insideCurrentDirPrefix) -and -not $normalizedPath.StartsWith($outsideCurrentDirPrefix) )
                {
                    $normalizedPath = $normalizedPath.Substring(2)
                }
            }
            [void]$globPaths.Add($normalizedPath)
        }
        else
        {
            $message = 'Resolve {0} ->' -f $Path
            $prefix = ' ' * ($message.Length - 3)
            Write-WhiskeyDebug -Context $TaskContext -Message $message

            if( -not [IO.Path]::IsPathRooted($normalizedPath) )
            {
                # Get the full path to the item
                $normalizedPath = Join-Path -Path $currentDir -ChildPath $result
            }

            # Remove all the '..' and '.' path parts from the path.
            if( -not [wildcardpattern]::ContainsWildcardCharacters($normalizedPath) )
            {
                $normalizedPath = [IO.Path]::GetFullPath($normalizedPath)
            }

            if( (Test-Path -Path $normalizedPath) )
            {
                $resolvedPaths = Get-Item -Path $normalizedPath -Force | Select-Object -ExpandProperty 'FullName'
            }

            if( -not $resolvedPaths )
            {
                if( -not $AllowNonexistent )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext `
                                     -Message ('{0}[{1}] "{2}" does not exist.' -f $PropertyName,$pathIdx,$Path)
                    return
                }

                $resolvedPaths = $normalizedPath

                # If it contains a wildcard, it didn't resolve to anything, so don't return it.
                if( [wildcardpattern]::ContainsWildcardCharacters($resolvedPaths) )
                {
                    return
                }
            }

            $expectedPathType = $PathType
            if( $expectedPathType -and -not $AllowNonexistent )
            {
                $itemType = 'Leaf'
                if( $expectedPathType -eq 'Directory' )
                {
                    $itemType = 'Container'
                }
                $invalidPaths = $resolvedPaths | Where-Object { -not (Test-Path -Path $_ -PathType $itemType) }
                if( $invalidPaths )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName $PropertyName -Message (@'
Found {0} paths that should resolve to a {1}, but don''t:

* {2}

'@ -f ($invalidPaths | Measure-Object).Count,$expectedPathType.ToLowerInvariant(),($invalidPaths -join ('{0}* ' -f [Environment]::NewLine)))
                    return
                }
            }

            $pathCount = $resolvedPaths | Measure-Object | Select-Object -ExpandProperty 'Count'
            if( $OnlySinglePath -and $pathCount -gt 1 )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName $CmdParameter.Name -Message (@'
    The value "{1}" resolved to {2} paths [1] but this task requires a single path. Please change "{1}" to a value that resolves to a single item.

    If you are this task''s author, and you want this property to accept multiple paths, please update the "{3}" command''s "{0}" property so it''s type is "[String[]]".

    [1] The {1} path resolved to:

    * {4}

'@ -f $CmdParameter.Name,$Path,$pathCount,$TaskContext.TaskName,($resolvedPaths -join ('{0}* ' -f [Environment]::NewLine)))
            }

            if( $Create )
            {
                if( -not $PathType )
                {
                    Write-WhiskeyError -Message ('The ValidatePath attribute on the "{0}" task''s "{1}" property has Create set to true but the attribute doesn''t specify a value for the PathType property. This is a task authoring error. The task''s author must update this ValidatePath attribute to either remove its Create property (so Whiskey doesn''t try to create non-existent items) or add a PathType property and set its value to either "File" or "Directory" (so Whiskey knows what kind of item to create).' -f $TaskContext.TaskName,$CmdParameter.Name) -ErrorAction Stop
                    return
                }

                foreach( $item in $resolvedPaths )
                {
                    if( (Test-Path -Path $item) )
                    {
                        continue
                    }

                    New-Item -Path $item -ItemType $PathType -Force | Out-Null
                }
            }
        }

        if( $resolvedPaths )
        {
            Resolve-WRelativePath -Path $resolvedPaths -DebugPrefix $prefix
        }
    }

    end
    {
        if( -not $UseGlob )
        {
            return
        }

        $globPathsStats = $globPaths | Measure-Object -Maximum -Property 'Length'
        $longestPathLength = $globPathsStats.Maximum
        $messageFormat = 'Resolve {{0,-{0}}} ->' -f $longestPathLength
        $message = $messageFormat -f ($globPaths | Select-Object -First 1)
        $prefix = ' ' * ($message.Length - 3)
        Write-WhiskeyDebug -Context $TaskContext -Message $message

        $messageFormat = $messageFormat -replace '^Resolve','       '
        foreach( $globPath in ($globPaths | Select-Object -Skip 1) )
        {
            Write-WhiskeyDebug -Context $TaskContext -Message ($messageFormat -f $globPath)
        }

        # Detect the case-sensitivity of the current directory so we can do a case-sensitive search if current directory
        # is on a case-sensitive file system.
        $parentPath = ''
        # Split-Path throws an exception if passed / in PowerShell Core.
        if( $currentDir -ne [IO.Path]::DirectorySeparatorChar -and $currentDir -ne [IO.Path]::AltDirectorySeparatorChar )
        {
            $parentPath = Split-Path -Path $currentDir -ErrorAction Ignore
        }
        $childName = Split-Path -Leaf -Path $currentDir
        # If we're in the root of the file system.
        if( -not $parentPath -or -not $childName )
        {
            $childPath = Get-ChildItem -Path $currentDir | Select-Object -First 1 | Select-Object -ExpandProperty 'FullName'
            $parentPath = Split-Path -Path $childPath
            if( -not $parentPath )
            {
                $parentPath = [IO.Path]::DirectorySeparatorChar
            }
            $childName = Split-Path -Leaf  -Path $childPath
        }

        $caseSensitivePath = [Text.StringBuilder]::New((Join-Path -Path $parentPath -ChildPath $childName))
        for( $idx = $caseSensitivePath.Length - 1; $idx -ge 0; --$idx )
        {
            $char = $caseSensitivePath[$idx]
            $isUpper = [char]::IsUpper($char)
            $isLower = [char]::IsLower($char)
            if( -not ($isUpper -or $isLower) )
            {
                # Not a character so move on to the next.
                continue
            }

            if( $isUpper )
            {
                $caseSensitivePath[$idx] = [char]::ToLower($char)
                break
            }

            $caseSensitivePath[$idx] = [char]::ToUpper($char)
        }
        $caseSensitive = -not (Test-Path -Path $caseSensitivePath.ToString())
        # We only want to hit the file system once, since globs are pretty greedy.
        $resolvedPaths =
            Find-GlobFile -Path $currentDir -Include $globPaths -Exclude $Exclude -Force -CaseSensitive:$caseSensitive |
            Select-Object -ExpandProperty 'FullName'

        if( -not $resolvedPaths )
        {
            if( -not $AllowNonexistent )
            {
                $pluralSuffix = ''
                if( $globPathsStats.Count -gt 1 )
                {
                    $pluralSuffix = '(s)'
                }
                $exclusionFilters = ''
                if( $Exclude )
                {
                    $exclusionFilters = ' (and excluding "{0}")' -f ($Exclude -join ', ')
                }

                Stop-WhiskeyTask -TaskContext $TaskContext `
                                    -Message ('{0}: glob pattern{1} "{2}"{3} did not match any files.' -f $PropertyName,$pluralSuffix,($globPaths -join ', '),$exclusionFilters)
            }
            return
        }

        Resolve-WRelativePath -Path $resolvedPaths -DebugPrefix $prefix
    }
}
