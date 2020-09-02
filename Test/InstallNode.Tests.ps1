
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:context = $null
}

function ThenNodeInstalled
{
    Test-Path -Path (Join-Path -Path $script:testRoot -ChildPath '.node') -PathType Container | Should -BeTrue
}

function WhenInstallingNode
{
    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testRoot
    Invoke-WhiskeyTask -TaskContext $context -Parameter $parameters -Name 'InstallNode'
}

Describe 'InstallNode' {
    It 'Should install node'{
        Init
        WhenInstallingNode
        ThenNodeInstalled
    }
}
