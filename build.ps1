[CmdletBinding(DefaultParameterSetName='Build')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Clean')]
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean,

    [Parameter(Mandatory=$true,ParameterSetName='Initialize')]
    [Switch]
    # Initializes the repository.
    $Initialize,

    [string]
    $PipelineName
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

$buildInfo = ''
if( Test-Path -Path ('env:APPVEYOR') )
{
    $commitID = $env:APPVEYOR_REPO_COMMIT
    $commitID = $commitID.Substring(0,7)

    $branch = $env:APPVEYOR_REPO_BRANCH
    $branch = $branch -replace '[^A-Za-z0-9-]','-'

    $buildInfo = '+{0}.{1}.{2}' -f $env:APPVEYOR_BUILD_NUMBER,$branch,$commitID
}

$assemblyVersion = @"
[assembly: System.Reflection.AssemblyVersion("$version")]
[assembly: System.Reflection.AssemblyFileVersion("$version")]
[assembly: System.Reflection.AssemblyInformationalVersion("$version$buildInfo")]
"@

$assemblyVersionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assembly\Whiskey\Properties\AssemblyVersion.cs'
if( -not (Test-Path -Path $assemblyVersionPath -PathType Leaf) )
{
    '' | Set-Content -Path $assemblyVersionPath
}

$currentAssemblyVersion = Get-Content -Path $assemblyVersionPath -Raw
if( $assemblyVersion -ne $currentAssemblyVersion.Trim() )
{
    Write-Verbose -Message ('Assembly version has changed.')
    $assemblyVersion | Set-Content -Path $assemblyVersionPath
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\VSSetup')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Functions\Use-CallerPreference.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Functions\Get-MSBuild.ps1')

$msbuild = Get-MSBuild -ErrorAction Ignore | Where-Object { $_.Name -eq '15.0' } | Select-Object -First 1
if( -not $msbuild )
{
    Write-Error ('Unable to find MSBuild 15.0.')
}

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin\NuGet.exe'
& $nugetPath restore (Join-Path -Path $PSScriptRoot -ChildPath 'Assembly\Whiskey.sln')

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

$ErrorActionPreference = 'Continue'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Get-ChildItem 'env:' |
    Where-Object { $_.Name -notin @( 'POWERSHELL_GALLERY_API_KEY', 'GITHUB_ACCESS_TOKEN' ) } |
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

if( $PipelineName )
{
    $optionalArgs['PipelineName'] = $PipelineName
}

$context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath
$apiKeys = @{
                'PowerShellGallery' = 'POWERSHELL_GALLERY_API_KEY'
                'github.com' = 'GITHUB_ACCESS_TOKEN'
            }

$apiKeys.Keys |
    Where-Object { Test-Path -Path ('env:{0}' -f $apiKeys[$_]) } |
    ForEach-Object {
        $apiKeyID = $_
        $envVarName = $apiKeys[$apiKeyID]
        Write-Verbose ('Adding API key "{0}" with value from environment variable "{1}".' -f $apiKeyID,$envVarName)
        Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value (Get-Item -Path ('env:{0}' -f $envVarName)).Value
    }
Invoke-WhiskeyBuild -Context $context @optionalArgs
