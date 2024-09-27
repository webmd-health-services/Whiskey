
function Get-TaskArgument
{
    [CmdletBinding()]
    param(
        # The task who's arguments to get.
        [Parameter(Mandatory)]
        [Whiskey.TaskAttribute] $Task,

        # The properties from the tasks's YAML.
        [Parameter(Mandatory)]
        [hashtable] $Property,

        # The current context.
        [Parameter(Mandatory)]
        [Whiskey.Context] $Context
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    # Allow snake_case syntax for property names.
    $propertyNames = $Property.Keys | ForEach-Object { $_ }
    foreach ($propertyName in $propertyNames)
    {
        if ($propertyName -notmatch '_')
        {
            continue
        }

        $camelCasePropertyName = $propertyName -replace '_', ''
        if ($Property.ContainsKey($camelCasePropertyName))
        {
            continue
        }

        $Property[$camelCasePropertyName] = $Property[$propertyName]
    }

    # Parameters of the actual command.
    $cmdParameters =
        Get-Command -Name $Task.CommandName |
        Select-Object -ExpandProperty 'Parameters'

    # Parameters to pass to the command.
    $taskArgs = @{ }

    [Management.Automation.ParameterMetadata]$cmdParameter = $null

    foreach( $cmdParameter in $cmdParameters.Values )
    {
        $propertyName = $cmdParameter.Name

        $value = $null

        if ($Property.ContainsKey($propertyName))
        {
            $value = $Property[$propertyName]
        }
        else
        {
            if ($propertyName -eq $Task.DefaultParameterName -and $Property.ContainsKey(''))
            {
                $value = $Property['']
            }
            else
            {
                foreach ($aliasName in $cmdParameter.Aliases)
                {
                    $value = $Property[$aliasName]
                    if ($Property.ContainsKey($aliasName))
                    {
                        $msg = "Property ""${aliasName}"" is deprecated. Rename to ""${propertyName}"" instead."
                        Write-WhiskeyWarning -Context $Context -Message $msg
                        break
                    }
                }
            }
        }

        # PowerShell can't implicitly convert strings to bool/switch values so we have to do it.
        if( $cmdParameter.ParameterType -eq [switch] -or $cmdParameter.ParameterType -eq [bool] )
        {
            $value = $value | ConvertFrom-WhiskeyYamlScalar
        }

        [Whiskey.Tasks.ParameterValueFromVariableAttribute]$valueFromVariableAttr =
            $cmdParameter.Attributes |
            Where-Object { $_ -is [Whiskey.Tasks.ParameterValueFromVariableAttribute] }

        if( $valueFromVariableAttr )
        {
            $value = Resolve-WhiskeyVariable -InputObject ('$({0})' -f $valueFromVariableAttr.VariableName) `
                                             -Context $Context
        }

        [Whiskey.Tasks.ValidatePathAttribute]$validatePathAttribute =
            $cmdParameter.Attributes |
            Where-Object { $_ -is [Whiskey.Tasks.ValidatePathAttribute] }

        if( $validatePathAttribute )
        {
            $params = @{ }

            $params['CmdParameter'] = $cmdParameter
            $params['ValidatePathAttribute'] = $validatePathAttribute
            $value = $value | Resolve-WhiskeyTaskPath -TaskContext $Context -TaskParameter $Property @params
        }

        # If the user didn't provide a value and we couldn't find one, don't pass anything.
        if( -not $Property.ContainsKey($propertyName) -and -not $value )
        {
            continue
        }

        $taskArgs[$propertyName] = $value
    }

    foreach( $name in @( 'TaskContext', 'Context' ) )
    {
        if( $cmdParameters.ContainsKey($name) )
        {
            $taskArgs[$name] = $Context
        }
    }

    foreach( $name in @( 'TaskParameter', 'Parameter' ) )
    {
        if( $cmdParameters.ContainsKey($name) )
        {
            $taskArgs[$name] = $Property
        }
    }

    return $taskArgs
}