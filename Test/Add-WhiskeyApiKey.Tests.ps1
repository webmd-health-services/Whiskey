
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null

function Init
{
    $script:context = $null
}

function ThenApiKey
{
    param(
        [Parameter(Mandatory)]
        [String]$ID,

        [Parameter(Mandatory)]
        [String]$WithValue,

        [Parameter(Mandatory)]
        [switch]$Exists
    )

    It ('should add API key') {
        Get-WhiskeyApiKey -Context $context -ID $ID -PropertyName 'Fubar' | Should -Be $WithValue
        $context.ApiKeys[$ID] | Should -BeOfType 'securestring'
    }
}

function WhenAddingApiKey
{
    param(
        [Parameter(Mandatory)]
        [String]$ID,

        [Parameter(Mandatory)]
        [String]$WithValue
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper
    Add-WhiskeyApiKey -Context $context -ID $ID -Value $WithValue
}

Describe 'Add-WhiskeyApiKey' {
    Init
    WhenAddingApiKey 'fubar' -WithValue 'snafu'
    ThenApiKey 'fubar' -WithValue 'snafu' -Exists
}
