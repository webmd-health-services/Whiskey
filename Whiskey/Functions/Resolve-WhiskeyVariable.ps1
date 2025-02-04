
function Resolve-WhiskeyVariable
{
    <#
    .SYNOPSIS
    Replaces any variables in a string to their values.

    .DESCRIPTION
    The `Resolve-WhiskeyVariable` function replaces any variables in strings, arrays, or hashtables with their values.
    Variables have the format `$(VARIABLE_NAME)`. Variables are expanded in each item of an array. Variables are
    expanded in each value of a hashtable. If an array or hashtable contains an array or hashtable, variables are
    expanded in those objects as well, i.e. `Resolve-WhiskeyVariable` recursivelye expands variables in all arrays and
    hashtables.

    You can add variables to replace via the `Add-WhiskeyVariable` function. If a variable doesn't exist, environment
    variables are used. If a variable has the same name as an environment variable, the variable value is used instead
    of the environment variable's value. If no variable or environment variable is found, `Resolve-WhiskeyVariable` will
    write an error and return the origin string.

    See the [Variables](https://github.com/webmd-health-services/Whiskey/wiki/Variables) page on the [Whiskey
    wiki](https://github.com/webmd-health-services/Whiskey/wiki) for a list of variables.

    .EXAMPLE
    '$(COMPUTERNAME)' | Resolve-WhiskeyVariable

    Demonstrates that you can use environment variable as variables. In this case, `Resolve-WhiskeyVariable` would
    return the name of the current computer.

    .EXAMPLE
    @( '$(VARIABLE)', 4, @{ 'Key' = '$(VARIABLE') } ) | Resolve-WhiskeyVariable

    Demonstrates how to replace all the variables in an array. Any value of the array that isn't a string is ignored.
    Any hashtable in the array will have any variables in its values replaced. In this example, if the value of
    `VARIABLE` is 'Whiskey`, `Resolve-WhiskeyVariable` would return:

        @(
            'Whiskey',
            4,
            @{
                Key = 'Whiskey'
            }
        )

    .EXAMPLE
    @{ 'Key' = '$(Variable)'; 'Array' = @( '$(VARIABLE)', 4 ) 'Integer' = 4; } | Resolve-WhiskeyVariable

    Demonstrates that `Resolve-WhiskeyVariable` searches hashtable values and replaces any variables in any strings it
    finds. If the value of `VARIABLE` is set to `Whiskey`, then the code in this example would return:

        @{
            'Key' = 'Whiskey';
            'Array' = @(
                            'Whiskey',
                            4
                      );
            'Integer' = 4;
        }
    #>
    [CmdletBinding(DefaultParameterSetName='ByPipeline')]
    param(
        [Parameter(Mandatory,ValueFromPipeline,ParameterSetName='ByPipeline')]
        [AllowNull()]
        # The object on which to perform variable replacement/substitution. If the value is a string, all variables in
        # the string are replaced with their values.
        #
        # If the value is an array, variable expansion is done on each item in the array.
        #
        # If the value is a hashtable, variable replcement is done on each value of the hashtable.
        #
        # Variable expansion is performed on any arrays and hashtables found in other arrays and hashtables, i.e. arrays
        # and hashtables are searched recursively.
        [Object]$InputObject,

        [Parameter(ParameterSetName='ByName')]
        # The name of a single Whiskey variable to resolve.
        [String]$Name,

        [Parameter(Mandatory)]
        # The context of the current build. Necessary to lookup any variables.
        [Whiskey.Context]$Context,

        # If the input object is a hashtable, only replace values on properties that are included in this list. The
        # default is to do variable replacement on all values.
        [String[]] $Include,

        # If the input object is a hashtable, replace values on properties except those in this list. The default is to
        # do variable replacement on all values.
        [String[]] $Exclude
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( $Name )
        {
            $InputObject = '$({0})' -f $Name
        }

        $version = $Context.Version
        $prereleaseID = ''
        if ($version.Semver2 -and $version.SemVer2.Prerelease -match '^(.*)\..*$')
        {
            $prereleaseID = $Matches[1]
        }
        $buildInfo = $Context.BuildMetadata

        $sem1Version = ''
        if( $version.SemVer1 )
        {
            $sem1Version = '{0}.{1}.{2}' -f $version.SemVer1.Major,$version.SemVer1.Minor,$version.SemVer1.Patch
        }

        $sem2Version = ''
        if( $version.SemVer2 )
        {
            $sem2Version = '{0}.{1}.{2}' -f $version.SemVer2.Major,$version.SemVer2.Minor,$version.SemVer2.Patch
        }

        $wellKnownVariables = @{
            'WHISKEY_BUILD_ID' = $buildInfo.BuildID;
            'WHISKEY_BUILD_NUMBER' = $buildInfo.BuildNumber;
            'WHISKEY_BUILD_ROOT' = $Context.BuildRoot;
            'WHISKEY_BUILD_SERVER_NAME' = $buildInfo.BuildServer;
            'WHISKEY_BUILD_STARTED_AT' = $Context.StartedAt;
            'WHISKEY_BUILD_URI' = $buildInfo.BuildUri;
            'WHISKEY_ENVIRONMENT' = $Context.Environment;
            'WHISKEY_JOB_URI' = $buildInfo.JobUri;
            'WHISKEY_MSBUILD_CONFIGURATION' = (Get-WhiskeyMSBuildConfiguration -Context $Context);
            'WHISKEY_OUTPUT_DIRECTORY' = $Context.OutputDirectory;
            'WHISKEY_PIPELINE_NAME' = $Context.PipelineName;
            'WHISKEY_SCM_BRANCH' = $buildInfo.ScmBranch;
            'WHISKEY_SCM_COMMIT_ID' = $buildInfo.ScmCommitID;
            'WHISKEY_SCM_URI' = $buildInfo.ScmUri;
            'WHISKEY_SEMVER1' = $version.SemVer1;
            'WHISKEY_SEMVER1_VERSION' = $sem1Version;
            'WHISKEY_SEMVER2' = $version.SemVer2;
            'WHISKEY_SEMVER2_NO_BUILD_METADATA' = $version.SemVer2NoBuildMetadata;
            'WHISKEY_SEMVER2_PRERELEASE_ID' = $prereleaseID
            'WHISKEY_SEMVER2_VERSION' = $sem2Version;
            'WHISKEY_TASK_NAME' = $Context.TaskName;
            'WHISKEY_TEMP_DIRECTORY' = (Get-Item -Path ([IO.Path]::GetTempPath()));
            'WHISKEY_TASK_TEMP_DIRECTORY' = $Context.Temp;
            'WHISKEY_VERSION' = $version.Version;
        }
    }

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( $null -eq $InputObject -or $InputObject -is [scriptblock] )
        {
            return $InputObject
        }

        if( (Get-Member -Name 'Keys' -InputObject $InputObject) )
        {
            $newValues = @{ }
            $toRemove = New-Object 'Collections.Generic.List[String]'
            # Can't modify a collection while enumerating it.
            foreach( $key in $InputObject.Keys )
            {
                if ($Include -and $key -notin $Include)
                {
                    continue
                }

                if ($Exclude -and $key -in $Exclude)
                {
                    continue
                }

                $newKey = $key | Resolve-WhiskeyVariable -Context $Context
                if( $newKey -ne $key )
                {
                    $toRemove.Add($key)
                }
                $newValues[$newKey] = Resolve-WhiskeyVariable -Context $Context -InputObject $InputObject[$key]
            }
            foreach( $key in $newValues.Keys )
            {
                $InputObject[$key] = $newValues[$key]
            }
            $toRemove | ForEach-Object { $InputObject.Remove($_) } | Out-Null
            return $InputObject
        }

        if( (Get-Member -Name 'Count' -InputObject $InputObject) )
        {
            for( $idx = 0; $idx -lt $InputObject.Count; ++$idx )
            {
                $InputObject[$idx] = Resolve-WhiskeyVariable -Context $Context -InputObject $InputObject[$idx]
            }
            return ,$InputObject
        }

        $startAt = 0
        $haystack = $InputObject.ToString()
        do
        {
            # Parse the variable expression, everything between $( and )
            $needleStart = $haystack.IndexOf('$(',$startAt)
            if( $needleStart -lt 0 )
            {
                break
            }
            elseif( $needleStart -gt 0 )
            {
                if( $haystack[$needleStart - 1] -eq '$' )
                {
                    $haystack = $haystack.Remove($needleStart - 1, 1)
                    $startAt = $needleStart
                    continue
                }
            }

            # Variable expressions can contain method calls, which begin and end with parenthesis, so
            # make sure you don't treat the close parenthesis of a method call as the close parenthesis
            # to the current variable expression.
            $needleEnd = $needleStart + 2
            $depth = 0
            while( $needleEnd -lt $haystack.Length )
            {
                $currentChar = $haystack[$needleEnd]
                if( $currentChar -eq ')' )
                {
                    if( $depth -eq 0 )
                    {
                        break
                    }

                    $depth--
                }
                elseif( $currentChar -eq '(' )
                {
                    $depth++
                }
                ++$needleEnd
            }

            $variableName = $haystack.Substring($needleStart + 2, $needleEnd - $needleStart - 2)
            $memberName = $null
            $arguments = $null

            # Does the variable expression contain a method call?
            if( $variableName -match '([^.]+)\.([^.(]+)(\(([^)]+)\))?' )
            {
                $variableName = $Matches[1]
                $memberName = $Matches[2]
                $arguments = $Matches[4]
                $arguments = & {
                                    if( -not $arguments )
                                    {
                                        return
                                    }

                                    $currentArg = New-Object 'Text.StringBuilder'
                                    $currentChar = $null
                                    $inString = $false
                                    # Parse each of the arguments in the method call. Each argument is
                                    # seperated by a comma. Ignore whitespace. Commas and whitespace that
                                    # are part of an argument must be double or single quoted. To include
                                    # a double quote inside a double-quoted string, double it. To include
                                    # a single quote inside a single-quoted string, double it.
                                    for( $idx = 0; $idx -lt $arguments.Length; ++$idx )
                                    {
                                        $nextChar = ''
                                        if( ($idx + 1) -lt $arguments.Length )
                                        {
                                            $nextChar = $arguments[$idx + 1]
                                        }

                                        $currentChar = $arguments[$idx]
                                        if( $currentChar -eq '"' -or $currentChar -eq "'" )
                                        {
                                            if( $inString )
                                            {
                                                if( $nextChar -eq $currentChar )
                                                {
                                                    [Void]$currentArg.Append($currentChar)
                                                    $idx++
                                                    continue
                                                }
                                            }

                                            $inString = -not $inString
                                            continue
                                        }

                                        if( $currentChar -eq ',' -and -not $inString )
                                        {
                                            $currentArg.ToString()
                                            [Void]$currentArg.Clear()
                                            continue
                                        }

                                        if( $inString -or -not [String]::IsNullOrWhiteSpace($currentChar) )
                                        {
                                            [Void]$currentArg.Append($currentChar)
                                        }
                                    }
                                    if( $currentArg.Length )
                                    {
                                        $currentArg.ToString()
                                    }
                               }

            }

            $envVarPath = 'env:{0}' -f $variableName
            if( $Context.Variables.ContainsKey($variableName) )
            {
                $value = $Context.Variables[$variableName]
            }
            elseif( $wellKnownVariables.ContainsKey($variableName) )
            {
                $value = $wellKnownVariables[$variableName]
            }
            elseif( [Environment] | Get-Member -Static -Name $variableName )
            {
                $value = [Environment]::$variableName
            }
            elseif( (Test-Path -Path $envVarPath) )
            {
                $value = (Get-Item -Path $envVarPath).Value
            }
            else
            {
                Write-WhiskeyError -Context $Context -Message ('Variable ''{0}'' does not exist. We were trying to replace it in the string ''{1}''. You can:

* Use the `Add-WhiskeyVariable` function to add a variable named ''{0}'', e.g. Add-WhiskeyVariable -Context $context -Name ''{0}'' -Value VALUE.
* Create an environment variable named ''{0}''.
* Prevent variable expansion by escaping the variable with a backtick or backslash, e.g. `$({0}) or \$({0}).
* Remove the variable from the string.
  ' -f $variableName,$InputObject) -ErrorAction $ErrorActionPreference
                return $InputObject
            }

            if ($null -eq $value)
            {
                $value = ''
            }

            if ($null -ne $value -and $memberName)
            {
                if( -not (Get-Member -Name $memberName -InputObject $value ) )
                {
                    Write-WhiskeyError -Context $Context -Message ('Variable ''{0}'' does not have a ''{1}'' member. Here are the available members:{2}    {2}{3}{2}    ' -f $variableName,$memberName,[Environment]::NewLine,($value | Get-Member | Out-String))
                    return $InputObject
                }

                if( $arguments )
                {
                    try
                    {
                        $value = $value.$memberName.Invoke($arguments)
                    }
                    catch
                    {
                        Write-WhiskeyError -Context $Context -Message ('Failed to call ([{0}]{1}).{2}(''{3}''): {4}.' -f $value.GetType().FullName,$value,$memberName,($arguments -join ''','''),$_)
                        return $InputObject
                    }
                }
                else
                {
                    $value = $value.$memberName
                }
            }

            $variableNumChars = $needleEnd - $needleStart + 1
            if( $needleStart + $variableNumChars -gt $haystack.Length )
            {
                Write-WhiskeyError -Context $Context -Message ('Unclosed variable expression ''{0}'' in value ''{1}''. Add a '')'' to the end of this value or escape the variable expression with a double dollar sign, e.g. ''${1}''.' -f $haystack.Substring($needleStart),$haystack)
                return $InputObject
            }

            $haystack = $haystack.Remove($needleStart,$variableNumChars)
            $haystack = $haystack.Insert($needleStart,$value)
            # No need to keep searching where we've already looked.
            $startAt = $needleStart
        }
        while( $true )

        return $haystack
    }
}
