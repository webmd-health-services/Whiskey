[CmdletBinding()]
param(
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean
)

#Requires -Version 4
Set-StrictMode -Version Latest

& (Join-Path -Path $PSScriptRoot -ChildPath 'init.ps1' -Resolve)

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Carbon' -Resolve) -Force
& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Get-ChildItem 'env:' | Out-String | Write-Verbose

$configuration = 'Release'

$toolParameters = @{
                        'NpmFeedUri' = 'https://npm.example.com/';
                        'NuGetFeedUri' = 'https://nuget.example.com/';
                        'PowerShellFeedUri' = 'https://powershell.example.com/';
                   }

$runningUnderBuildServer = Test-WhiskeyRunByBuildServer
if( $runningUnderBuildServer )
{
    $toolParameters['BBServerCredential'] = New-Credential -Username 'fubar' -Password 'snafu'
    $toolParameters['BBServerUri'] = 'https://bitbucketserver.example.com/'
    $toolParameters['ProGetCredential'] = New-Credential -Username 'fubar' -Password 'snafu'
}

try
{
    $cleanArg = @{ }
    if( $Clean )
    {
        $cleanArg['Clean'] = $true
    }

    $context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath -BuildConfiguration $configuration @toolParameters
    Invoke-WhiskeyBuild -Context $context @cleanArg
    exit 0
}
catch
{
    Write-Error -ErrorRecord $_
    exit 1
}

