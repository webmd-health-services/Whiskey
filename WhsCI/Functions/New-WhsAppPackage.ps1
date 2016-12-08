
function New-WhsAppPackage
{
    <#
    .SYNOPSIS
    Creates a WHS application deployment package.

    .DESCRIPTION
    The `New-WhsCIArtifact` function creates a package for a WHS application. It creates a universal ProGet package. The package should contain everything the application needs to install itself and run on any server it is deployed to, with minimal/no pre-requisites installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the package file.
        $OutputFile,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The paths to include in the artifact.
        $Path,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The whitelist of files to include in the artifact.
        $Whitelist
    )

    Set-StrictMode -Version 'Latest'

    $packageFileName = $OutputFile | Split-Path -Leaf
    $tempRoot = [IO.Path]::GetRandomFileName()
    $tempRoot = 'WhsCI+New-WhsAppPackage+{0}+{1}' -f $packageFileName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-String | Write-Verbose
    try
    {
        Get-Item -Path $Path | Compress-Item -OutFile $OutputFile
    }
    finally
    {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}