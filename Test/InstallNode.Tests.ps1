
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null

$script:latestNodeVersion = 
    Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | 
    Sort-Object | 
    Select-Object -ExpandProperty SyncRoot | 
    Where-Object{ $_.lts  } | 
    Select-Object -ExpandProperty version | 
    Select-Object -First 1

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
    $script:fileCreatedTime = New-Object Collections.ArrayList
    $script:nodePath = Join-Path -Path $script:testRoot -ChildPath '.node'
}

function ThenNodeInstalled
{
    param(
        [String]$Version
    )

    $nodePath | Should -Exist
    if( $Version )
    {
        Get-ChildItem -Path (Join-Path -Path $testRoot -ChildPath '.output') |
            Where-Object { $_.Name -match '(\d+\.\d+\.\d+)' } |
            Select-Object -ExpandProperty Name
        $Version | Should -Match ([regex]::Escape($Matches[1]))
    }
}

function WhenInstallingNode
{
    param(
        [String]$Version,

        [switch]$Force
    )

    if( $Force )
    {
        $parameters['Force'] = $true
    }
    $parameters['Version'] = $Version
    Invoke-WhiskeyTask -TaskContext $context `
                       -Parameter $parameters `
                       -Name 'InstallNode' `
                       -InformationAction SilentlyContinue

    $script:fileCreatedTime.add(((Get-ChildItem -Path $nodePath).CreationTime | Select-Object -ExpandProperty ticks))
}

function ThenNodeFolderDidNotChange
{
    @( $filecreatedTime | Select-Object -Unique ) | Should -HaveCount 1
}

Describe 'InstallNode' {
    It "should install latest Node.js $($latestNodeVersion)"{
        Init
        WhenInstallingNode
        ThenNodeInstalled -Version $latestNodeVersion
    }
}

Describe 'InstallNode.NodeJs 4_5_0' {
    It 'should install Node.js 4.5.0'{
        Init
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0'
    }
}

Describe 'InstallNode.NodeJs 4_5_0, then InstallNode with force' {
    It "should overwrite installed verion when using Force"{
        Init
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0'
        WhenInstallingNode -Force
        ThenNodeInstalled -Version $latestNodeVersion
    }
}

Describe 'InstallNode.node version 4_5.0, then InstallNode 4.5.0 again' {
    It 'should not overwrite if some version already installed' {
        Init
        WhenInstallingNode -Version '4.5.0'
        WhenInstallingNode -Version '4.5.0'
        ThenNodeInstalled -Version '4.5.0' 
        ThenNodeFolderDidNotChange
    }
}