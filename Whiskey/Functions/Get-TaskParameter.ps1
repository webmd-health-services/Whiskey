
function Get-TaskParameter
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        # The name of the command.
        $Name,

        [Parameter(Mandatory)]
        [hashtable]
        # The properties from the tasks's YAML.
        $TaskProperty,

        [Parameter(Mandatory)]
        [Whiskey.Context]
        # The current context.
        $Context
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    # Parameters of the actual command.
    $cmdParameters = Get-Command -Name $task.CommandName | Select-Object -ExpandProperty 'Parameters'

    # Parameters to pass to the command.
    $taskParameters = @{ }

    [Management.Automation.ParameterMetadata]$cmdParameter = $null

    foreach( $cmdParameter in $cmdParameters.Values )
    {
        $propertyName = $cmdParameter.Name

        $value = $TaskProperty[$propertyName]

        # PowerShell can't implicitly convert strings to bool/switch values so we have to do it.
        if( $cmdParameter.ParameterType -eq [Switch] -or $cmdParameter.ParameterType -eq [bool] )
        {
            $value = $value | ConvertFrom-WhiskeyYamlScalar
        }

        [Whiskey.Tasks.ParameterValueFromVariableAttribute]$valueFromVariableAttr = $cmdParameter.Attributes | Where-Object { $_ -is [Whiskey.Tasks.ParameterValueFromVariableAttribute] }
        if( $valueFromVariableAttr )
        {
            $value = Resolve-WhiskeyVariable -InputObject ('$({0})' -f $valueFromVariableAttr.VariableName) -Context $Context
        }

        [Whiskey.Tasks.ValidatePathAttribute]$validateAsPathAttr = $cmdParameter.Attributes | Where-Object { $_ -is [Whiskey.Tasks.ValidatePathAttribute] }
        if( $validateAsPathAttr )
        {
            $optionalParams = @{ }
            if( $validateAsPathAttr.PathType )
            {
                $optionalParams['PathType'] = $validateAsPathAttr.PathType
            }

            if( $value )
            {
                $value = $value | Resolve-WhiskeyTaskPath -TaskContext $Context -PropertyName $propertyName @optionalParams
            }
            if( -not $value -and $validateAsPathAttr.Mandatory )
            {
                $errorMsg = 'path "{0}" does not exist.' -f $TaskProperty[$propertyName]
                if( -not $TaskProperty[$propertyName] )
                {
                    $errorMsg = 'is mandatory.'
                }
                Stop-WhiskeyTask -TaskContext $Context -PropertyName $cmdParameter.Name -Message $errorMsg
            }

            $expectedPathType = $validateAsPathAttr.PathType 
            if( $value -and $expectedPathType )
            {
                $pathType = 'Leaf'
                if( $expectedPathType -eq 'Directory' )
                {
                    $pathType = 'Container'
                }
                $invalidPaths = 
                    $value | 
                    Where-Object { -not (Test-Path -Path $_ -PathType $pathType) }
                if( $invalidPaths )
                {
                    Stop-WhiskeyTask -TaskContext $Context -PropertyName $cmdParameter.Name -Message (@'
must be a {0}, but found {1} path(s) that are not:
 
* {2}
 
'@ -f $expectedPathType.ToLowerInvariant(),($invalidPaths | Measure-Object).Count,($invalidPaths -join ('{0}* ' -f [Environment]::NewLine)))
                }
            }

            $pathCount = $value | Measure-Object | Select-Object -ExpandProperty 'Count'
            if( $cmdParameter.ParameterType -ne ([string[]]) -and $pathCount -gt 1 )
            {
                Stop-WhiskeyTask -TaskContext $Context -PropertyName $cmdParameter.Name -Message (@'
The value "{1}" resolved to {2} paths [1] but this task requires a single path. Please change "{1}" to a value that resolves to a single item.
 
If you are this task''s author, and you want this property to accept multiple paths, please update the "{3}" command''s "{0}" property so it''s type is "[string[]]".
 
[1] The {1} path resolved to:
 
* {4}
 
'@ -f $cmdParameter.Name,$TaskProperty[$propertyName],$pathCount,$task.CommandName,($value -join ('{0}* ' -f [Environment]::NewLine)))
            }
        }

        # If the user didn't provide a value and we couldn't find one, don't pass anything.
        if( -not $TaskProperty.ContainsKey($propertyName) -and -not $value )
        {
            continue
        }

        $taskParameters[$propertyName] = $value
        $TaskProperty.Remove($propertyName)
    }

    foreach( $name in @( 'TaskContext', 'Context' ) )
    {
        if( $cmdParameters.ContainsKey($name) )
        {
            $taskParameters[$name] = $Context
        }
    }

    foreach( $name in @( 'TaskParameter', 'Parameter' ) )
    {
        if( $cmdParameters.ContainsKey($name) )
        {
            $taskParameters[$name] = $TaskProperty
        }
    }

    return $taskParameters
}
