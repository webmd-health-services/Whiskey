
function Get-WhiskeyApiKey
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
        $PropertyName
    )

    Set-StrictMode -Version 'Latest'

    return $TaskContext.ApiKeys[$ID]
}