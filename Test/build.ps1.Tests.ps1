
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

$buildPs1Path = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\build.ps1' -Resolve
function Init
{
    Get-Module 'PowerShellGet','Whiskey','PackageManagement' | Remove-Module -Force -ErrorAction Ignore
}

function ThenModule
{
    param(
        [Parameter(Mandatory)]
        [string[]]$Named,

        [switch]$Not,

        [Parameter(Mandatory)]
        [Switch]$Loaded
    )

    if( $Not )
    {
        Get-Module -Name $Named | Should -BeNullOrEmpty
    }
    else
    {
        Get-Module -Name $Named | Should -Not -BeNullOrEmpty
    }
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenWhiskeyInstalled
{
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'PSModules\Whiskey\*\Whiskey.ps*1'
    $path | Should -Exist
    $path | Get-Item | Should -HaveCount 2
}

function WhenBootstrapping
{
    $Global:Error.Clear()

    Copy-Item -Path $buildPs1Path -Destination $TestDrive.FullName

    & (Join-Path -Path $TestDrive.FullName -ChildPath 'build.ps1' -Resolve)
}

Describe 'buildPs1.when repo isn''t bootstrapped' {
    It 'should download latest version of Whiskey' {
        Init
        WhenBootstrapping
        ThenWhiskeyInstalled
        ThenNoErrors
        ThenModule 'PackageManagement','PowerShellGet' -Not -Loaded
        ThenModule 'Whiskey' -Loaded
    }
}

Describe 'buildPs1.when Whiskey gets a new major version' {
    It 'should bootstrap the latest version of the current major line' {
        $manifest = Test-ModuleManifest -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Whiskey.psd1' -Resolve)
        $defaultBootstrapVersion = ''
        foreach( $line in (Get-Content -Path $buildPs1Path) )
        {
            if( $line -match 'whiskeyVersion = ''([^'']+)''' )
            {
                $defaultBootstrapVersion = $Matches[1]
                break
            }
        }

        $defaultBootstrapVersion | Should -Not -BeNullOrEmpty -Because 'this test must be able to find the version of Whiskey to pin to in build.ps1'
        $manifest.Version | Should -BeLike $Matches[1] -Because 'build.ps1 should be kept in sync with module''s major version number'
    }
}