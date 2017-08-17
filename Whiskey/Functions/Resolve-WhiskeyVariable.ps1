
function Resolve-WhiskeyVariable
{
    <#
    .SYNOPSIS
    Replaces any variables in a string to their values.

    .DESCRIPTION
    The `Resolve-WhiskeyVariable` function replaces any variables in strings, arrays, or hashtables with their values. Variables have the format `$(VARIABLE_NAME)`. Variables are expanded in each item of an array. Variables are expanded in each value of a hashtable. If an array or hashtable contains an array or hashtable, variables are expanded in those objects as well, i.e. `Resolve-WhiskeyVariable` recursivelye expands variables in all arrays and hashtables.
    
    You can add variables to replace via the `Add-WhiskeyVariable` function. If a variable doesn't exist, environment variables are used. If a variable has the same name as an environment variable, the variable value is used instead of the environment variable's value. If no variable or environment variable is found, `Resolve-WhiskeyVariable` will write an error and return the origin string.

    Well-known Whiskey variables you can use are:

    * `MSBuildConfiguration`: the configuration used by the `MSBuild` task. Usually `Debug` when run by developers and `Release` on build servers.

    .EXAMPLE
    '$(COMPUTERNAME)' | Resolve-WhiskeyVariable

    Demonstrates that you can use environment variable as variables. In this case, `Resolve-WhiskeyVariable` would return the name of the current computer.

    .EXAMPLE
    @( '$(VARIABLE)', 4, @{ 'Key' = '$(VARIABLE') } ) | Resolve-WhiskeyVariable

    Demonstrates how to replace all the variables in an array. Any value of the array that isn't a string is ignored. Any hashtable in the array will have any variables in its values replaced. In this example, if the value of `VARIABLE` is 'Whiskey`, `Resolve-WhiskeyVariable` would return:

        @(
            'Whiskey',
            4,
            @{
                Key = 'Whiskey'
            }
        )

    .EXAMPLE
    @{ 'Key' = '$(Variable)'; 'Array' = @( '$(VARIABLE)', 4 ) 'Integer' = 4; } | Resolve-WhiskeyVariable

    Demonstrates that `Resolve-WhiskeyVariable` searches hashtable values and replaces any variables in any strings it finds. If the value of `VARIABLE` is set to `Whiskey`, then the code in this example would return:

        @{
            'Key' = 'Whiskey';
            'Array' = @(
                            'Whiskey',
                            4
                      );
            'Integer' = 4;
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]
        # The object on which to perform variable replacement/substitution. If the value is a string, all variables in the string are replaced with their values.
        #
        # If the value is an array, variable expansion is done on each item in the array. 
        #
        # If the value is a hashtable, variable replcement is done on each value of the hashtable. 
        #
        # Variable expansion is performed on any arrays and hashtables found in other arrays and hashtables, i.e. arrays and hashtables are searched recursively.
        $InputObject,

        [Parameter(Mandatory=$true)]
        [object]
        # The context of the current build. Necessary to lookup any variables.
        $Context
    )

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        if( (Get-Member -Name 'Keys' -InputObject $InputObject) )
        {
            # Can't modify a collection while enumerating it.
            $newValues = @{ }
            foreach( $key in $InputObject.Keys )
            {
                $newValues[$key] = Resolve-WhiskeyVariable -Context $Context -InputObject $InputObject[$key]
            }
            foreach( $key in $newValues.Keys )
            {
                $InputObject[$key] = $newValues[$key]
            }
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

        while( $InputObject -match '(\$\(([^)]+)\))' )
        {
            $variableName = $Matches[2]
            $envVarPath = 'env:{0}' -f $variableName
            if( $Context.Variables.ContainsKey($variableName) )
            {
                $value = $Context.Variables[$variableName]
            }
            elseif( (Test-Path -Path $envVarPath) )
            {
                $value = (Get-Item -Path $envVarPath).Value
            }
            else
            {
                Write-Error -Message ('Variable ''{0}'' does not exist. We were trying to replace it in the string ''{1}''. You can:
                
* Use the `Add-WhiskeyVariable` function to add a variable named ''{0}'', e.g. Add-WhiskeyVariable -Context $context -Name ''{0}'' -Value VALUE.
* Create an environment variable named ''{0}''.
* Prevent variable expansion by escaping the variable with a backtick or backslash, e.g. `$({0}) or \$({0}).
* Remove the variable from the string.
  ' -f $variableName,$InputObject) -ErrorAction $ErrorActionPreference
                return $InputObject
            }

            if( $value )
            {
                $InputObject = $InputObject -replace ([regex]::Escape($Matches[1]),$value)
            }
        }

        return $InputObject
    }
}
