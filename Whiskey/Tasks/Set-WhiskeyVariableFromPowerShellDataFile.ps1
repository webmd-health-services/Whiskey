
function Set-WhiskeyVariableFromPowerShellDataFile
{
    [CmdletBinding()]
    [Whiskey.Task('SetVariableFromPowerShellDataFile')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory)]
        [hashtable]
        $TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [string]
        $Path
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $data = Import-PowerShellDataFile -Path $Path
    if( -not $data )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Path' -Message ('Failed to parse PowerShell Data File "{0}". Make sure this is a properly formatted PowerShell data file. Use the `Import-PowerShellDataFile` cmdlet.' -f $Path)
        return
    }

    function Set-VariableFromData
    {
        param(
            [object]
            $Variable,

            [hashtable]
            $Data,
            
            [string]
            $ParentPropertyName = ''
        )

        foreach( $propertyName in $Variable.Keys )
        {
            $variableName = $Variable[$propertyName]
            if( -not $Data.ContainsKey($propertyName) )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Variables' -Message ('PowerShell Data File "{0}" does not contain "{1}{2}" property.' -f $Path,$ParentPropertyName,$propertyName)
                continue
            }

            $variableValue = $Data[$propertyName]
            if( $variableName | Get-Member 'Keys' )
            {
                Set-VariableFromData -Variable $variableName -Data $variableValue -ParentPropertyName ('{0}{1}.' -f $ParentPropertyName,$propertyName)
                continue
            }

            Add-WhiskeyVariable -Context $TaskContext -Name $variableName -Value $variableValue
        }
    }

    Set-VariableFromData -Variable $TaskParameter['Variables'] -Data $data
}