
function Install-WhiskeyNuGet
{
    <#
    .SYNOPSIS
    Installs NuGet from its NuGet package.

    .DESCRIPTION
    The `Install-WhiskeyNuGet` function installs NuGet from its NuGet package. It returns the path to the `NuGet.exe` from the package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        # Where to install NuGet.
        [string]$DownloadRoot,

        # The version to download.
        [string]$Version
        
    )

    Set-StrictMode -version 'Latest'  
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $versionParam = @{ }
    if( $Version )
    {
        $versionParam['Version'] = $Version
    }

    $nuGetPath = Install-WhiskeyNuGetPackage -Name 'NuGet.CommandLine' -DownloadRoot $DownloadRoot @versionParam
    return Join-Path -Path $nuGetPath -ChildPath 'tools\NuGet.exe' -Resolve
}