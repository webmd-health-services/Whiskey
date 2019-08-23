
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

function Init
{
    Get-Module 'PowerShellGet','Whiskey','PackageManagement' | Remove-Module -Force -Verbose #-ErrorAction Ignore
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
    (Join-Path -Path $TestDrive.FullName -ChildPath 'PSModules\Whiskey') | Should -Exist
}

function WhenBootstrapping
{
    $Global:Error.Clear()

    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\build.ps1' -Resolve) `
              -Destination $TestDrive.FullName

    & (Join-Path -Path $TestDrive.FullName -ChildPath 'build.ps1' -Resolve) -Verbose
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