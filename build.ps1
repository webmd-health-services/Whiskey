[CmdletBinding()]
param(
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean
)

#Requires -Version 4
Set-StrictMode -Version Latest

#& (Join-Path -Path $PSScriptRoot -ChildPath 'init.ps1' -Resolve)

Invoke-Command -ScriptBlock {
                                $VerbosePreference = 'SilentlyContinue'
                                Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Carbon' -Resolve) -Force
                            }
& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Get-ChildItem 'env:' | Out-String | Write-Verbose

$configuration = 'Release'

try
{
    $cleanArg = @{ }
    if( $Clean )
    {
        $cleanArg['Clean'] = $true
    }

    $context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath
    Invoke-WhiskeyBuild -Context $context @cleanArg
    exit 0
}
catch
{
    Write-Error -ErrorRecord $_
    exit 1
}

