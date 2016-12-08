
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
    $tempBaseName = 'WhsCI+New-WhsAppPackage+{0}' -f $packageFileName
    $tempRoot = '{0}+{1}' -f $tempBaseName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-String | Write-Verbose
    try
    {
        foreach( $item in $Path )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempRoot -ChildPath $itemName
            robocopy $item $destination /MIR $Whitelist | Write-Debug
        }

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $OutputFile
    }
    finally
    {
        Get-ChildItem -Path $env:TEMP -Filter ('{0}+*' -f $tempBaseName) |
            Remove-Item -Recurse -Force 
    }
}