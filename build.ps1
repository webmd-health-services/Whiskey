[CmdletBinding()]
param(
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean,

    [Switch]
    # Initializes the repository.
    $Initialize
)

#Requires -Version 4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Get-ChildItem 'env:' | 
    Where-Object { $_.Name -ne 'POWERSHELL_GALLERY_API_KEY' } |
    Format-Table |
    Out-String | 
    Write-Verbose

$optionalArgs = @{ }
if( $Clean )
{
    $optionalArgs['Clean'] = $true
}

if( $Initialize )
{
    $optionalArgs['Initialize'] = $true
}

$context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath
if( (Test-Path -Path 'env:POWERSHELL_GALLERY_API_KEY') )
{
    Add-WhiskeyApiKey -Context $context -ID 'PowerShellGallery' -Value $env:POWERSHELL_GALLERY_API_KEY
}
Invoke-WhiskeyBuild -Context $context @optionalArgs
