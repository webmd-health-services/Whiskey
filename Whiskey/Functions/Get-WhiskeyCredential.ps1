
function Get-WhiskeyCredential
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        $ID,

        [Parameter(Mandatory=$true)]
        [string]
        $PropertyName,

        [string]
        $PropertyDescription
    )

    Set-StrictMode -Version 'Latest'

    if( -not $TaskContext.Credentials.ContainsKey($ID) )
    {
        $propertyDescriptionParam = @{ }
        if( $PropertyDescription )
        {
            $propertyDescriptionParam['PropertyDescription'] = $PropertyDescription
        }
        Stop-WhiskeyTask -TaskContext $Context `
                         -Message ('Credential ''{0}'' does not exist in Whiskey''s credential store. Use the `Add-WhiskeyCredential` function to add this credential, e.g. `Add-WhiskeyCredential -Context $context -ID ''{0}'' -Credential $credential`.' -f $ID) `
                         @propertyDescriptionParam
    }

    return $TaskContext.Credentials[$ID]
}