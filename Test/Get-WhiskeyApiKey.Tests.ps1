
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$threwException = $null
$credential = $null

function WhenGettingApiKey
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        $PropertyName
    )

    $context = New-WhiskeyTestContext -ForBuildServer -ForTaskName 'SomeTask'
    $Global:Error.Clear()
    $credential = $null
    $script:threwException = $false
    try
    {
        $credential = Get-WhiskeyApiKey -Context $context -ID 'FuBar' -PropertyName $PropertyName
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

function ThenNoApiKeyReturned
{
    It ('should not return an api key') {
        $credential | Should -BeNullOrEmpty
    }
}

function ThenThrewAnException
{
    param(
        $Pattern
    )

    It ('should throw an exception') {
        $threwException | Should -Be $true
    }

    It ('the error message should match /{0}/' -f $Pattern) {
        $Global:Error | Should -Match $Pattern
    }
}

Describe 'Get-WhiskeyApiKey.when credential doesn''t exist' {
    WhenGettingApiKey -PropertyName 'FubarID' -ErrorAction SilentlyContinue
    ThenThrewAnException 'does not exist'
    ThenThrewAnException '\bFubarID\b'
    ThenNoApiKeyReturned
}
