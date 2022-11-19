function Get-InstalledDotNetSdk
{
    <#
    .SYNOPSIS
    Finds all installed .NET Core SDK versions.
    
    .DESCRIPTION
    The `Get-InstalledDotNetSdk` function scans the local filesystem for existing versions of the .NET Core and returns a list of installed .NET Core SDK versions based on the location of the available `dotnet` executable files.

    .EXAMPLE
    Get-InstalledDotNetSdk

    Returns all installed .NET SDK Versions as a list of strings.
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
            $installedVersions += 
                Get-ChildItem $sdkPath | 
                Where-Object {
                    ($_.Name -match '\d+\.\d+\.\d{3,}') -and
                    ( Get-ChildItem -Path $_.FullName )
                } |
                ForEach-Object { $_.Name }
        }
        if ( $installedVersions.Length -gt 0 )
        {
            return $installedVersions
        }
    }
}