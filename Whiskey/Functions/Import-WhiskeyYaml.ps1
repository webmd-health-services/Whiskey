
function Import-WhiskeyYaml
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='FromFile')]
        [String]$Path,

        [Parameter(Mandatory,ParameterSetName='FromString')]
        [String]$Yaml
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $PSCmdlet.ParameterSetName -eq 'FromFile' )
    {
        $Yaml = Get-Content -Path $Path -Raw
    }

    $builder = New-Object 'YamlDotNet.Serialization.DeserializerBuilder'
    $deserializer = $builder.Build()

    $reader = New-Object 'IO.StringReader' $Yaml
    $config = @{}
    try
    {
        $config = $deserializer.Deserialize( $reader )
    }
    catch
    {
        if( $PSCmdlet.ParameterSetName -eq 'FromFile' )
        {
            Write-WhiskeyError "Whiskey configuration file ""$($Path)"" cannot be parsed: $($_)." -ErrorAction Stop
        }
        else
        {
            Write-WhiskeyError "YAML cannot be parsed: $($_)$([Environment]::NewLine * 2)$($Yaml)" -ErrorAction Stop
        }
    }
    finally
    {
        $reader.Close()
    }
    if( -not $config )
    {
        $config = @{}
    }

    if( $config -is [String] )
    {
        $config = @{ $config = '' }
    }

    function ConvertTo-CaseInsensitiveObject
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, ValueFromPipeline)]
            [Object] $InputObject
        )

        process
        {
            if ($InputObject -is [Collections.IDictionary])
            {
                $hashtable = [ordered]@{}

                Add-Member -InputObject $hashtable -Name 'ContainsKey' -MemberType ScriptMethod -Value {
                    param(
                        [String] $Key
                    )

                    return $this.Contains($Key)
                }

                foreach ($key in $InputObject.Keys)
                {
                    # Don't pipe! We don't want to enumerate values here.
                    $hashtable[$key] = ConvertTo-CaseInsensitiveObject -InputObject $InputObject[$key]
                }

                return $hashtable
            }

            if ($InputObject -is [Collections.IList])
            {
                return $InputObject | ConvertTo-CaseInsensitiveObject
            }

            return $InputObject
        }
    }

    $config = $config | ConvertTo-CaseInsensitiveObject

    return $config
}
