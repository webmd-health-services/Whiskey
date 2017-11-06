function Get-ProGetAsset
{
    <#
        .SYNOPSIS
        Gets assets from ProGet. 

        .DESCRIPTION
        Get-ProGetAsset gets assets from ProGet. A session and Directory is required. 
        An optional asset name may be added to get the content of the file. 
        If no asset name is added the function will return a list of all files in the asset directory.

        .EXAMPLE
        Get-ProGetAsset -Session $session -Name 'myAsset' -Directory 'versions'
        
        Returns contents of 'myAsset' if asset is found, otherwise returns 404.

        .Example
        Get-ProGetAsset -Session $session -Directory 'versions'
        
        Returns list of files in the versions asset directory. If no files found an empty list is returned.

    #>
    param(
        [Parameter(Mandatory = $true)]
        [Object]
        $Session,

        [Parameter(Mandatory = $true)]
        [string]
        $Directory,        

        [string]
        $Name
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $path = '/endpoints/{0}/dir' -f $Directory

    try
    {
        return Invoke-ProGetRestMethod -Session $Session -Path $path -Method Get | Where-Object { $_ -match $Name}
    }
    catch
    {
        Write-Error ("ERROR: {0}" -f $Global:Error)
    }
}
