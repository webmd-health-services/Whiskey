
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
            Write-WhiskeyError "Whiskey configuration file ""$($Path)"" cannot be parsed" -ErrorAction Stop
        }
        else
        {
            Write-WhiskeyError "YAML cannot be parsed: $([Environment]::NewLine) $Yaml" -ErrorAction Stop
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

    return $config
}
