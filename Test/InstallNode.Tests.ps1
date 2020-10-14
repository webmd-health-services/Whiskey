
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null

$script:latestNodeVersion = 
    Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | 
    Sort-Object | 
    Select-Object -ExpandProperty SyncRoot | 
    Where-Object{ $_.lts -ne $false } | 
    Select-Object -ExpandProperty version | 
    Select-Object -First 1

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:context = $null
    $script:fileCreatedTime = New-Object Collections.ArrayList
}

function ThenNodeInstalled
{
    param(
        [String]$Version
    )

    $nodePath = Join-Path -Path $script:testRoot -ChildPath '.node'
    Test-Path -Path $nodePath -PathType Container | Should -BeTrue
    if($Version)
    {
        Get-ChildItem -Path $nodePath | Where-Object { $_.Name -match '\d+\.\d+\.\d+' } | Select-Object -ExpandProperty Name
        $Version -match $Matches[0] | Should -BeTrue
    }
}

function WhenInstallingNode
{
    param(
        [String]$Version
    )

    $nodePath = Join-Path -Path $script:testRoot -ChildPath '.node'
    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testRoot
    $parameters = @{
        'Version' = $Version
    }
    Invoke-WhiskeyTask -TaskContext $context -Parameter $parameters -Name 'InstallNode' 
    $script:fileCreatedTime.add(((Get-ChildItem -Path $nodePath).CreationTime | Select-Object -ExpandProperty ticks))
}

function WhenInstallingNodeForce
{
    param(
        [String]$Version
    )
    $parameters = @{
        'Force' = $true
        'Version' = $Version
    }
    Invoke-WhiskeyTask -TaskContext $context -Parameter $parameters -Name 'InstallNode'
}

function ThenNodeFolderDidNotChange
{
    @( $filecreatedTime | Select-Object -Unique ).Count -eq 1 | Should -BeTrue
}

Describe 'InstallNode' {
    It "Should install latest Node.js $($latestNodeVersion)"{
        Init
        WhenInstallingNode
        ThenNodeInstalled -Version $latestNodeVersion
    }
}

Describe 'InstallNode Node.js 4.5.0' {
    It 'Should install Node.js 4.5.0'{
        Init
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0'
    }
}

Describe 'InstallNode Node.js 4.5.0, then InstallNode with force' {
    It "Should overwrite Node.js 4.5.0 with Node.js $($latestNodeVersion)"{
        Init
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0'
        WhenInstallingNodeForce
        ThenNodeInstalled -Version $latestNodeVersion
    }
}

Describe 'InstallNode node version 4.5.0, then InstallNode 4.5.0 again' {
    It 'Should not overwrite old node folder'{
        Init
        WhenInstallingNode -Version '4.5.0'
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0' 
        ThenNodeFolderDidNotChange
    }
}