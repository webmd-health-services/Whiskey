
function Add-WhiskeyTaskDefault
{
    <#
    .SYNOPSIS
    Sets default values for task parameters.

    .DESCRIPTION
    The `Add-WhiskeyTaskDefault` function adds default values for task parameters in the `TaskDefaults` property of the task context object. The function will ensure that the context object already contains a `TaskDefaults` property and if not will throw an error. The given `TaskName` will also be validated to ensure it is a known valid Whiskey task name, if not an error is thrown. The function will only set a task default if an existing default does not already exist, otherwise an error will be thrown. To overwrite an existing task default use the `Force` parameter.

    .EXAMPLE
    Add-WhiskeyTaskDefault -Context $context -TaskName 'MSBuild' -Parameter 'Version' -Value 12.0

    Demonstrates setting the default value of the `MSBuild` task's `Version` parameter to `12.0`.

    .EXAMPLE
    Add-WhiskeyTaskDefault -Context $context -TaskName 'MSBuild' -Parameter 'Version' -Value 15.0 -Force

    Demonstrates overwriting the current default value for `MSBuild` task's `Version` parameter to `15.0`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [object]
        # The current build context. Use `New-WhiskeyContext` to create context objects.
        $Context,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of the task that a default parameter value will be set.
        $TaskName,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of the task parameter to set a default value for.
        $ParameterName,

        [Parameter(Mandatory=$true)]
        # The default value for the task parameter.
        $Value,

        [switch]
        # Overwrite an existing task default with a new value.
        $Force
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if (-not ($Context | Get-Member -Name 'TaskDefaults'))
    {
        throw 'The given ''Context'' object does not contain a ''TaskDefaults'' property. Create a proper Whiskey context object using the ''New-WhiskeyContext'' function.'
    }

    if ($TaskName -notin (Get-WhiskeyTask | Select-Object -ExpandProperty 'Name'))
    {
        throw 'The TaskName ''{0}'' is not a valid Whiskey task.' -f $TaskName
    }

    if ($context.TaskDefaults.ContainsKey($TaskName))
    {
        if ($context.TaskDefaults[$TaskName].ContainsKey($ParameterName) -and -not $Force)
        {
            throw 'The ''{0}'' task already contains a default value for the parameter ''{1}''. Use the ''Force'' parameter to overwrite the current value.' -f $TaskName,$ParameterName
        }
        else
        {
            $context.TaskDefaults[$TaskName][$ParameterName] = $Value
        }
    }
    else
    {
        $context.TaskDefaults[$TaskName] = @{ $ParameterName = $Value }
    }
}
