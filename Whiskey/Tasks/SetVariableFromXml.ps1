
function Set-WhiskeyVariableFromXml
{
    [Whiskey.Task("SetVariableFromXml")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String]$Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyVerbose -Context $TaskContext -Message ($Path)
    [xml]$xml = $null
    try
    {
        $xml = Get-Content -Path $Path -Raw
    }
    catch
    {
        $Global:Error.RemoveAt(0)
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Exception reading XML from file "{0}": {1}"' -f $Path,$_)
        return
    }

    $nsManager = New-Object -TypeName 'Xml.XmlNamespaceManager' -ArgumentList $xml.NameTable
    $prefixes = $TaskParameter['NamespacePrefixes']
    if( $prefixes -and ($prefixes | Get-Member 'Keys') )
    {
        foreach( $prefix in $prefixes.Keys )
        {
            $nsManager.AddNamespace($prefix, $prefixes[$prefix])
        }
    }

    $allowMissingNodes = $TaskParameter['AllowMissingNodes'] | ConvertFrom-WhiskeyYamlScalar

    $variables = $TaskParameter['Variables']
    if( $variables -and ($variables | Get-Member 'Keys') )
    {
        foreach( $variableName in $variables.Keys )
        {
            $xpath = $variables[$variableName]
            $value = $xml.SelectNodes($xpath, $nsManager) | ForEach-Object {
                if( $_ | Get-Member 'InnerText' )
                {
                    $_.InnerText
                }
                elseif( $_ | Get-Member '#text' )
                {
                    $_.'#text'
                }
            }
            $exists = ' '
            if( $value -eq $null )
            {
                if( -not $allowMissingNodes )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Variable {0}: XPath expression "{1}" matched no elements/attributes in XML file "{2}".' -f $variableName,$xpath,$Path)
                    return
                }
                $value = ''
                $exists = '!'
            }
            Write-WhiskeyVerbose -Context $TaskContext -Message ('  {0} {1}' -f $exists,$xpath)
            Write-WhiskeyVerbose -Context $TaskContext -Message ('        {0} = {1}' -f $variableName,($value | Select-Object -First 1))
            $value | Select-Object -Skip 1 | ForEach-Object {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('        {0}   {1}' -f (' ' * $variableName.Length),$_)
            }
            Add-WhiskeyVariable -Context $TaskContext -Name $variableName -Value $value
        }
    }
}
