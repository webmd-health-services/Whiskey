
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$failed = $true

function GivenVariable
{
    param(
        $Name,
        $Value
    )

    Add-WhiskeyVariable -Context $context -Name $Name -Value $Value
}

function Init
{
    $script:context = New-WhiskeyTestContext -ForBuildServer
}

function WhenCallingTask
{
    [CmdletBinding()]
    param(
        $Parameter
    )

    $script:failed = $false
    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'SetVariable' -Parameter $Parameter
    }
    catch
    {
        Write-Error $_
        $script:failed = $true
    }
}

function ThenTaskFailed
{
    param(
        $Regex
    )

    It ('should fail') {
        $failed | Should -Be $true
        $Global:Error | Should -Match $Regex
    }
}

function ThenVariable
{
    param(
        $Name,
        $Is
    )

    It ('should set a variable''s value') {
        $context.Variables[$Name] | Should -Be $Is
    }
}

Describe 'SetVariable.when adding new variables' {
    Init
    WhenCallingTask @{ Variable1 = 'Value1' }
    ThenVariable 'Variable1' -Is 'Value1'
}

Describe 'SetVariable.when adding multiple variables' {
    Init
    WhenCallingTask @{ Variable1 = 'Value1' ; Variable2 = 'Value 2' }
    ThenVariable 'Variable1' -Is 'Value1'
    ThenVariable 'Variable2' -Is 'Value 2'
}

Describe 'SetVariable.when variable exists' {
    Init
    GivenVariable 'Variable1' 'Value1'
    WhenCallingTask @{ Variable1 = 'Value2' }
    ThenVariable 'Variable1' -Is 'Value2'
}

Describe 'SetVariable.when setting a pre-defined Whiskey variable' {
    Init
    WhenCallingTask @{ 'WHISKEY_SCM_BRANCH' = 'fubar' } -ErrorAction SilentlyContinue
    ThenTaskFailed ([regex]::Escape('is a built-in Whiskey variable'))
}