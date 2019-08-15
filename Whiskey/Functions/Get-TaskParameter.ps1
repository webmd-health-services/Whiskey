
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
            $params = @{ }

            $params['PropertyName'] = $propertyName
            $params['CmdParameter'] = $cmdParameter
            $params['ValidateAsPathAttr'] = $validateAsPathAttr
            $value = $value | Resolve-WhiskeyTaskPathParameter -TaskContext $Context @params
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
