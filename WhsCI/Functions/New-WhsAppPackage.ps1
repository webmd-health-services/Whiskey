
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
        # The name of the package being created.
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        # A description of the package.
        $Description,

        [Parameter(Mandatory=$true)]
        [string]
        # The package's version.
        $Version,

        [Parameter(Mandatory=$true)]
        [string]
        # The directory where the package file should be saved. This directory will be created if it doesn't exist.
        $OutputDirectory,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The paths to include in the artifact.
        $Path,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The whitelist of files to include in the artifact. Wildcards supported. Only files that match entries in this list are included in the package.
        $Include,
        
        [string[]]
        # A list of files and/or directories to exclude. If any file or directory that would match a pattern in the `Include` list matches an item in this list, it is not included in the package.
        $Exclude
    )

    Set-StrictMode -Version 'Latest'

    $fileName = '{0}.{1}.upack' -f $Name,$Version
    $outFile = Join-Path -Path $OutputDirectory -ChildPath $fileName
    Install-Directory -Path $OutputDirectory

    $tempRoot = [IO.Path]::GetRandomFileName()
    $tempBaseName = 'WhsCI+New-WhsAppPackage+{0}' -f $Name
    $tempRoot = '{0}+{1}' -f $tempBaseName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-String | Write-Verbose
    $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
    @{
        name = $Name;
        version = $Version;
        title = $Name;
        description = $Description
    } | ConvertTo-Json | Set-Content -Path $upackJsonPath

    try
    {
        foreach( $item in $Path )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempRoot -ChildPath $itemName
            $excludeParams = $Exclude | ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
            robocopy $item $destination /MIR $Include 'upack.json' $excludeParams | Write-Debug
        }

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $outFile
    }
    finally
    {
        Get-ChildItem -Path $env:TEMP -Filter ('{0}+*' -f $tempBaseName) |
            Remove-Item -Recurse -Force 
    }
}