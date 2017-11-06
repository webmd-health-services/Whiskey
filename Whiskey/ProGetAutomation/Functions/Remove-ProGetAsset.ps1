function Remove-ProGetAsset
{
    <#
        .SYNOPSIS
        Removes assets from ProGet. 

        .DESCRIPTION
        The `Remove-ProGetAsset` function removes assets from ProGet. A session, assetName and assetDirectory is required. 

        .EXAMPLE
        Remove-ProGetAsset -Session $session -AssetName $ProGetAssetName -AssetDirectory 'Versions'

        Removes assetName if file is found.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [Object]
        $Session,

        [Parameter(Mandatory = $true)]
        [string]
        $Directory,        

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $path = '/endpoints/{0}/content/{1}' -f $Directory, $Name
    try
    {
        Invoke-ProGetRestMethod -Session $Session -Path $path -Method Delete
    }
    catch
    {
        Write-Error ("ERROR: {0}" -f $Global:Error)
    }
}
