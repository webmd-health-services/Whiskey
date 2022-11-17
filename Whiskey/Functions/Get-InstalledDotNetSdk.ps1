function Get-InstalledDotNetSdk
{
    <#
    .SYNOPSIS
    Finds all installed .NET Core SDK versions.
    
    .DESCRIPTION
    The `Get-InstalledDotNetSdk` function scans the local filesystem for existing versions of the .NET Core and returns a list of installed .NET Core SDK versions based on the location of the available `dotnet` executable files.

    .EXAMPLE
    Get-InstalledDotNetSdk

    Returns all installed .NET SDK Versions.
    #>
    $dotnetPaths = Get-Command -Name 'dotnet' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source'
    if ( -not $dotnetPaths )
    {
        Write-WhiskeyWarning -Message 'No installed .NET Core SDK Versions found.'
        return
    }
    Write-WhiskeyVerbose -Message "Gathering all installed .NET Core SDK Versions"
    if ( $dotnetPaths )
    {
        $installedVersions = @()
        foreach( $dotnetPath in $dotnetPaths )
        {
            $sdkPath = Join-Path -Path ($dotnetPath | Split-Path -Parent) -ChildPath 'sdk'
            Write-WhiskeyError $sdkPath
            $installedVersions += 
                Get-ChildItem $sdkPath | 
                Where-Object {
                    ($_.Name -match '\d+\.\d+\.\d{3,}') -and
                    ( Get-ChildItem -Path $_.FullName )
                } |
                ForEach-Object {
                    $_.Name -match '^(\d+)\.(\d+)\.(\d{1})(\d+)' | Out-Null
                    Write-WhiskeyError $_.Name
                    [Version] "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
                }
        }
        if ( $installedVersions.Length -gt 0 )
        {
            return $installedVersions
        }
    }
}