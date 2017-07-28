
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$threwException = $null
$credential = $null

function WhenGettingCredential
{
    param(
        $PropertyDescription
    )

    $optionalParams = @{ }
    if( $PropertyDescription )
    {
        $optionalParams['PropertyDescription'] = $PropertyDescription
    }

    $context = New-WhiskeyTestContext -ForBuildServer
    $Global:Error.Clear()
    $credential = $null
    $script:threwException = $false
    try
    {
        $credential = Get-WhiskeyCredential -Context $context -ID 'FuBar' -PropertyName 'FubarID' @optionalParams
    }
    catch
    {
        $script:threwException = $true
    }
}

function ThenNoCredentialReturned
{
    It ('should not return a credential') {
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

Describe 'Get-WhiskeyCredential.when credential doesn''t exist' {
    WhenGettingCredential
    ThenThrewAnException 'does not exist'
    ThenNoCredentialReturned
}


Describe 'Get-WhiskeyCredential.when passing property name' {
    WhenGettingCredential -PropertyDescription 'fubar snafu'
    ThenThrewAnException 'fubar\ snafu'
}

