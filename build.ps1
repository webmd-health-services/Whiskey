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

# Build the assembly first!

$manifest = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Whiskey.psd1') -Raw
if( $manifest -notmatch '\bModuleVersion\b\s*=\s*(''|")([^''"]+)' )
{
    Write-Error -Message 'Unable to find the module version in the Whiskey manifest.' -ErrorAction Stop
}
$version = $Matches[2]

dotnet build '--configuration' 'Release' ('-p:Version={0}' -f $version) 'Assembly\Whiskey.sln'
if( $LASTEXITCODE )
{
    exit 1
}

$nugetExePath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin\NuGet.exe' -Resolve
& $nugetExePath 'install' 'xunit.runner.console' '-Version' '2.3.1' '-OutputDirectory' 'packages'

$xunitConsoleExePath = Join-Path -Path $PSScriptRoot -ChildPath 'packages\xunit.runner.console.2.3.1\tools\net452\xunit.console.exe'
& $xunitConsoleExePath 'Assembly\SemanticVersionTest\bin\Release\SemanticVersionTest.dll'
if( $LASTEXITCODE )
{
    exit 1
}

robocopy 'Assembly\Whiskey\bin\Release\netstandard2.0' 'Whiskey\bin' '*.dll' '/NP'
if( $LASTEXITCODE -ge 8 )
{
    exit 1
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
