[CmdletBinding()]
param(
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean,

    [Switch]
    # Initializes the repository.
    $Initialize
)

$ErrorActionPreference = 'Stop'
#Requires -Version 4
Set-StrictMode -Version Latest

# We can't use Whiskey to build Whiskey's assembly because we need Whiskey's assembly to use Whiskey.
$manifest = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Whiskey.psd1') -Raw
if( $manifest -notmatch '\bModuleVersion\b\s*=\s*(''|")([^''"]+)' )
{
    Write-Error -Message 'Unable to find the module version in the Whiskey manifest.'
}
$version = $Matches[2]

$commitID = git rev-parse HEAD
$commitID = $commitID.Substring(0,7)

$branch = git rev-parse --abbrev-ref HEAD
$branch = $branch -replace '[^A-Za-z0-9-]','-'

$assemblyVersion = @"
[assembly: System.Reflection.AssemblyVersion("$version")]
[assembly: System.Reflection.AssemblyFileVersion("$version")]
[assembly: System.Reflection.AssemblyInformationalVersion("$version+$branch.$commitID")]
"@ 

$assemblyVersionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assembly\Whiskey\Properties\AssemblyVersion.cs'

$currentAssemblyVersion = Get-Content -Path $assemblyVersionPath -Raw
if( $assemblyVersion -ne $currentAssemblyVersion.Trim() )
{
    Write-Verbose -Message ('Assembly version has changed.')
    $assemblyVersion | Set-Content -Path $assemblyVersionPath
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\VSSetup')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Functions\Get-MSBuild.ps1')

$msbuild = Get-MSBuild -ErrorAction Ignore | Where-Object { $_.Name -eq '15.0' }
if( -not $msbuild )
{
    Write-Error ('Unable to find MSBuild 15.0.')
}

& $msbuild.Path /target:build ('/property:Version={0}' -f $version) '/property:Configuration=Release' 'Assembly\Whiskey.sln' '/v:m'
if( $LASTEXITCODE )
{
    exit 1
}

$whiskeyBinPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin'
$whiskeyOutBinPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assembly\Whiskey\bin\Release'
foreach( $assembly in (Get-ChildItem -Path $whiskeyOutBinPath -Filter '*.dll') )
{
    $destinationPath = Join-Path -Path $whiskeyBinPath -ChildPath $assembly.Name
    if( (Test-Path -Path $destinationPath -PathType Leaf) )
    {
        $sourceHash = Get-FileHash -Path $assembly.FullName
        $destinationHash = Get-FileHash -Path $destinationPath
        if( $sourceHash.Hash -eq $destinationHash.Hash )
        {
            continue
        }
    }

    Copy-Item -Path $assembly.FullName -Destination $whiskeyBinPath
}

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
