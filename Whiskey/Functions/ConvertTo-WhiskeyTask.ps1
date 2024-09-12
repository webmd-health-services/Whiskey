
function ConvertTo-WhiskeyTask
{
    <#
    .SYNOPSIS
    Converts an object parsed from a whiskey.yml file into a task name and task parameters.

    .DESCRIPTION
    The `ConvertTo-WhiskeyTask` function takes an object parsed from a whiskey.yml file and converts it to a task name
    and hashtable of parameters and returns both in that order.

    .EXAMPLE
    $name,$parameter = ConvertTo-WhiskeyTask -InputObject $parsedTask
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]$InputObject
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ($InputObject)
    {
        # Build:
        # - TaskName
        # - command
        if( $InputObject -is [String] )
        {
            $InputObject
            @{ }
            return
        }
        elseif ($InputObject | Get-Member -Name 'Keys')
        {
            # Build:
            # - TaskName:
            #      Property1: Value1
            #      Property2: Value2
            if ($InputObject.Count -eq 1)
            {
                $taskName = $InputObject.Keys | Select-Object -First 1
                $parameter = $InputObject[$taskName]
                if( -not $parameter )
                {
                    $parameter = @{ }
                }
                elseif( -not ($parameter | Get-Member -Name 'Keys') )
                {
                    $parameter = @{ '' = $parameter }
                }

            }
            # Build:
            # - Exec: Command
            #   Property1: Value1
            #   Property2: Value2
            # - PowerShell: ScriptBlock
            #   Property3: Value3
            else
            {
                $taskName = $InputObject.Keys | Select-Object -First 1
                $parameter = @{ '' = $InputObject[$taskName] }
                $InputObject.Keys | Select-Object -Skip 1 | ForEach-Object { $parameter[$_] = $InputObject[$_] }
            }

            $taskName
            $parameter
            return
        }
    }

    # Convert back to YAML to display its invalidness to the user.
    $builder = New-Object 'YamlDotNet.Serialization.SerializerBuilder'
    $yamlWriter = New-Object "System.IO.StringWriter"
    $serializer = $builder.Build()
    $serializer.Serialize($yamlWriter, $InputObject)
    $yaml = $yamlWriter.ToString()
    $yaml = $yaml -split [regex]::Escape([Environment]::NewLine) |
                Where-Object { @( '...', '---' ) -notcontains $_ } |
                ForEach-Object { '    {0}' -f $_ }
    Write-WhiskeyError -Message ('Invalid task YAML:{0} {0}{1}{0}A task must have a name followed by optional parameters, e.g.

    Build:
    - Task1
    - Task2:
        Parameter1: Value1
        Parameter2: Value2

    ' -f [Environment]::NewLine,($yaml -join [Environment]::NewLine))
}
